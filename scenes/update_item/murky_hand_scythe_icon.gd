extends CharacterBody2D

signal is_go_back
signal kill_enemy

@onready var fly_timer = $FlyTimer
@onready var surround_timer = $SurroundTimer
@onready var sprite_2d = $Sprite2D


var equip_damage: int
var equip_knockback: int

var accel: float
var speed: int = 400
var speed_time: float = 0.1

var first_point: Vector2

var dir: Vector2
var dir_v: Vector2

var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_point = self.global_position
	dir = Vector2.RIGHT.rotated(global_rotation  )
	fly_timer.start()
	velocity = dir * speed

func _physics_process(delta):
	
	if fly_timer.time_left > 0:
		dir_v = dir
	elif surround_timer.time_left > 0:
		dir = (self.global_position - first_point).normalized()
		dir_v.x = -dir.y
		dir_v.y = dir.x
	else:
		dir_v = (player.global_position - self.global_position).normalized()
		if global_position.distance_to(player.global_position) < 15:
			is_go_back.emit()
			queue_free()
	accel = speed / speed_time
	velocity.x = move_toward(velocity.x, dir_v.x * speed, accel * delta)
	velocity.y = move_toward(velocity.y, dir_v.y * speed, accel * delta)
	
	move_and_slide()
	
	sprite_2d.rotation += delta * 15

func _on_fly_timer_timeout():
	surround_timer.start()

func _on_area_2d_body_entered(body):
	
	if body.is_in_group("Enemy"):
		var hit_direction = (body.position - player.position).normalized()
		body.hurt_damage = max(1, equip_damage * player.stats.equip_damage * player.stats.global_damage)
		body.hurt_knockback = player.stats.bullet_knockback * 1.5
		body.hurt_direction = hit_direction
		if randf_range(0,100) < player.stats.critical_luck:
			body.hurt_damage *= player.stats.critical_damage
			body.is_critical_hit = true
		body.emit_signal("is_hurt")
		GameEvents.emit_equip_hit_enemy(body, self)
		if body.stats.hp <=0:
			GameEvents.emit_equip_kill_enemy()
			kill_enemy.emit()
