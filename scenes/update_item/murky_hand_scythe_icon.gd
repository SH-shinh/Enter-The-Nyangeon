extends HitBox

signal is_go_back
signal kill_enemy

@onready var fly_timer = $FlyTimer
@onready var surround_timer = $SurroundTimer
@onready var sprite_2d = $Sprite2D
@onready var collision_shape_2d = $CollisionShape2D


var equip_damage: int
var equip_knockback: int

var accel: float
var speed: int = 400
var speed_time: float = 0.1

var first_point: Vector2

var dir: Vector2
var dir_v: Vector2

var player: Node

var velocity: Vector2
var body_group: Array[Node]

var is_idle: int = 1

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.global_time_count.connect(time_count)
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)

func idle_state():
	is_idle = 1
	self.visible = false
	global_position = Vector2.ZERO
	collision_shape_2d.disabled = true

func active_state():
	is_idle = 0
	self.visible = true
	collision_shape_2d.disabled = false
	dir = Vector2.RIGHT.rotated(global_rotation)
	velocity = dir * speed
	fly_timer.start()
	first_point = self.global_position
	apply_melee_damage_data()

func _physics_process(delta):
	
	if is_idle == 1:
		return
	
	if fly_timer.time_left > 0:
		dir_v = dir
	elif surround_timer.time_left > 0:
		dir = (self.global_position - first_point).normalized()
		dir_v.x = -dir.y
		dir_v.y = dir.x
	else:
		dir_v = (player.global_position - self.global_position).normalized()
		if global_position.distance_to(player.global_position) < 15:
			idle_state()
			is_go_back.emit()
	accel = speed / speed_time
	velocity.x = move_toward(velocity.x, dir_v.x * speed, accel * delta)
	velocity.y = move_toward(velocity.y, dir_v.y * speed, accel * delta)
	
	global_position += velocity * delta
	sprite_2d.rotation += delta * 15

func time_count():
	if is_idle == 1:
		return
	
	add_damage_data()

func apply_melee_damage_data():
	if damage_data == null:
		damage_data = DamageData.new()
	else:
		damage_data.reset_data()
	
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		damage_data.base_damage = max(1, equip_damage * PlayerData.kick_damage_mult * player.stats.equip_damage * player.stats.global_damage * player.stats.critical_damage)
		damage_data.is_crit = true
	else:
		damage_data.base_damage = max(1, equip_damage * PlayerData.kick_damage_mult * player.stats.equip_damage * player.stats.global_damage)
		damage_data.is_crit = false
	
	damage_data.knockback_force = max( player.stats.bullet_knockback + 50, 1)
	damage_data.knockback_direction = Vector2.RIGHT.rotated(global_rotation)
	damage_data.damage_type.append(GameTags.MELEE_DAMAGE)
	damage_data.source_node = self.get_path()
	damage_data.source_type.append(GameTags.EQUIP)
	damage_data.on_damage_dealt.append(func(victim: Node, _actual_damage: float):
		if victim.stats.hp <= 0:
			kill_enemy.emit()
		)

func add_damage_data():
	if !body_group.is_empty():
		for i in body_group:
			if i == null or not is_instance_valid(i):
				continue
			i.hit_received.emit(damage_data)

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

func _on_area_entered(hurtbox: Area2D):
	if hurtbox is HurtBox and !body_group.has(hurtbox):
		body_group.push_back(hurtbox)

func _on_area_exited(hurtbox: Area2D):
	
	if hurtbox is HurtBox and body_group.has(hurtbox):
		body_group.remove_at(body_group.find(hurtbox))
