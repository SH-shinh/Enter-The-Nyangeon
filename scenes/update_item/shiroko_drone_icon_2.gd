extends CharacterBody2D

signal shot_missile(missile: Node)

var dir: Vector2 = Vector2.ZERO
var dir2: Vector2 = Vector2.ZERO
var dir_v: Vector2 = Vector2.ZERO
var is_look_at: Vector2

var speed: int = 350
const speed_time: float = 0.1
var accel: float

var extra_shoot_time: int = 5

var enemy_body: Array =[]

var shoot_cd_timer_mult: float = 1
var shiroko_drone_damage_add: int = 0
var can_shoot: bool = true

var player: Node

@onready var shiroko_drone = $%ShirokoDrone
@onready var shoot_cd_timer = $ShootCDTimer
@onready var fire_sounds = $FireSounds
@onready var shoot_position = $ShootPosition

@onready var missile = preload("res://scenes/update_item/shiro_missile.tscn")

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	shot_missile.connect(missile_hurt_damage)
	GameEvents.player_critical_hit_enemy.connect(extra_shoot)
	GameEvents.screen_changed.connect(outline_changed)

func outline_changed(n: float):
	$CanvasGroup.material.set_shader_parameter("outline_width", n)

func _physics_process(delta):
	dir = player.global_position
	dir2 = (dir - global_position).normalized()
	speed = min(650, global_position.distance_to(dir) * 1.3 * global_position.distance_to(dir) / 100)
	accel = speed / speed_time
	if dir2 != null:
		if global_position.distance_to(dir) > 80:
			dir_v = dir2
		else:
			dir_v.x = dir2.y
			dir_v.y = -dir2.x
	velocity.x = move_toward(velocity.x, dir_v.x * speed, accel * delta)
	velocity.y = move_toward(velocity.y, dir_v.y * speed, accel * delta)
	move_and_slide()
	
	if enemy_body.size() != 0:
		is_look_at = (enemy_body[0].global_position - self.global_position).normalized()
		shiroko_drone.v = is_look_at.angle()
		if can_shoot == true and shoot_cd_timer.time_left <= 0:
			auto_shot.call_deferred()
	else:
		if player != null:
			is_look_at = (player.crosshair_pos - self.global_position).normalized()
			shiroko_drone.v = is_look_at.angle()
		else:
			is_look_at = dir_v
			shiroko_drone.v = is_look_at.angle()

func emit_shot_missile(missile: Node):
	shot_missile.emit(missile)

func missile_hurt_damage(bullet_body: Node):
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		bullet_body.is_critical = true
		bullet_body.equip_damage = max(1, floor((20 + shiroko_drone_damage_add) * player.stats.equip_damage * player.stats.explosion_damage * player.stats.global_damage * PlayerData.bullet_damage_mult *  player.stats.critical_damage))
		#GameEvents.emit_player_shot_critical(bullet_body)
	else:
		bullet_body.equip_damage = max(1, (20 + shiroko_drone_damage_add) * player.stats.equip_damage * player.stats.explosion_damage * player.stats.global_damage * PlayerData.bullet_damage_mult)
		#GameEvents.emit_player_shot_not_critical(bullet_body)
	
	bullet_body.equip_knockback = player.stats.bullet_knockback
	bullet_body.explosion_range = 5 * player.stats.explosion_range * 0.6

func auto_shot():
	shoot_cd_timer.wait_time = 3 * shoot_cd_timer_mult
	shoot_cd_timer.start()
	_shoot_missile()
	can_shoot = false

func _shoot_missile():
	if player.stats.bullet_count == 1:
		
		var now_missile = PoolManager.get_pool("shiro_missile")
		var add_missile: bool = false
		
		if now_missile == null or now_missile.is_idle == 0:
			now_missile = missile.instantiate()
			add_missile = true
		
		now_missile.position = shoot_position.global_position
		now_missile.kill_time = 110
		now_missile.global_rotation = is_look_at.angle()
		shoot_position.rotation = is_look_at.angle()
		fire_sounds.play()
		
		now_missile.active_state()
		if add_missile == true:
			get_tree().get_first_node_in_group("BulletRoot").add_child(now_missile)
			
		emit_shot_missile(now_missile)
		GameEvents.emit_equip_shot_position(shoot_position.global_position,now_missile)
	
	else:
		for i in player.stats.bullet_count:
			
			var now_missile = PoolManager.get_pool("shiro_missile")
			var add_missile: bool = false
			
			if now_missile == null or now_missile.is_idle == 0:
				now_missile = missile.instantiate()
				add_missile = true
			
			now_missile.position = shoot_position.global_position
			now_missile.kill_time = 110
			
			var arc_rad = deg_to_rad(player.stats.bullet_arc)
			var increment = arc_rad / (player.stats.bullet_count - 1)
			now_missile.global_rotation = (
				is_look_at.angle() +
				increment * i -
				arc_rad / 2
			)
			
			now_missile.active_state()
			if add_missile == true:
				get_tree().get_first_node_in_group("BulletRoot").add_child(now_missile)
			
			emit_shot_missile(now_missile)
			GameEvents.emit_equip_shot_position(shoot_position.global_position,now_missile)
		
		fire_sounds.play()

func sort_enemy():
	if enemy_body.size() != 0:
		enemy_body.sort_custom(
			func(x, y):
				return x.global_position.distance_to(self.global_position) < y.global_position.distance_to(self.global_position)
		)

func extra_shoot(bullet_body: Node):
	extra_shoot_time -= 1
	if extra_shoot_time <= 0:
		_shoot_missile.call_deferred()
		extra_shoot_time = 5

func _on_track_box_body_entered(body):
	if body.is_in_group("Enemy"):
		enemy_body.append(body)
	sort_enemy()

func _on_track_box_body_exited(body):
	if body.is_in_group("Enemy")  and enemy_body.has(body):
		enemy_body.remove_at(enemy_body.find(body))
	sort_enemy()


func _on_shoot_cd_timer_timeout():
	can_shoot = true
