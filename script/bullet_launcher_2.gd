extends Node2D

signal can_move

@export var shoot_at_once:bool = true
@export var bullet_scale: float = 1
@export var bullet_count: int
@export_range(0, 360) var bullet_arc :float
@export var bullet: PackedScene
@export var bullet_damage: float
@export var bullet_speed: float
@export var bullet_penetrate: int
@export var collision_num: int
@export var decay_time: float
@export var decay_speed: int
@export var kill_time: float
@export var explosion_range: float
@export var shoot_bullet_num: int
@export var offset: float = 0
@export var offset_x: float = 0
@export var delay_time: float = 0.1
@export var bullet_id: String
var bullet_damage_mult: float = 1


@onready var shoot_position = $ShootPosition
@onready var timer = $Timer

func _ready():
	shoot_position.position.x = offset_x + offset
	if shoot_at_once == true:
		shoot_bullet()

func emit_can_move():
	can_move.emit()

func shoot_bullet():
	#var first_r = global_rotation
	
	timer.wait_time = delay_time
	
	if bullet_count == 1:
		
		var now_bullet = PoolManager.get_pool(bullet_id)
		var add_bullet: bool = false
		if now_bullet == null or now_bullet.is_idle == 0:
			now_bullet = bullet.instantiate()
			add_bullet = true
		
		now_bullet.scale = Vector2(bullet_scale,bullet_scale)
		now_bullet.bullet_damage =  bullet_damage * bullet_damage_mult
		now_bullet.speed = bullet_speed
		now_bullet.penetrate = bullet_penetrate
		now_bullet.collision_num = collision_num
		now_bullet.decay_time = decay_time * 10
		now_bullet.decay_speed = decay_speed
		now_bullet.kill_time = kill_time * 10
		now_bullet.shoot_bullet_num = shoot_bullet_num
		if explosion_range > 0:
			now_bullet.explosion_range = explosion_range
		now_bullet.global_position = shoot_position.global_position
		now_bullet.global_rotation = global_rotation
		can_move.connect(now_bullet.is_stop_false)
		
		now_bullet.active_state()
		if add_bullet == true:
			get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
		
	
	else:
		var direction: Vector2 = global_position \
			.direction_to(get_global_mouse_position()) \
			.normalized()
		
		for i in bullet_count:
			
			var now_bullet = PoolManager.get_pool(bullet_id)
			var add_bullet: bool = false
			if now_bullet == null or now_bullet.is_idle == 0:
				now_bullet = bullet.instantiate()
				add_bullet = true
			
			now_bullet.scale = Vector2(bullet_scale,bullet_scale)
			now_bullet.bullet_damage =  bullet_damage
			now_bullet.speed = bullet_speed
			now_bullet.penetrate = bullet_penetrate
			now_bullet.collision_num = collision_num
			now_bullet.decay_time = decay_time * 10
			now_bullet.decay_speed = decay_speed
			now_bullet.kill_time = kill_time * 10
			now_bullet.shoot_bullet_num = shoot_bullet_num
			now_bullet.is_stop = true
			if !can_move.is_connected(now_bullet.is_stop_false):
				can_move.connect(now_bullet.is_stop_false)
			if explosion_range > 0:
				now_bullet.explosion_range = explosion_range
			
			var arc_rad = deg_to_rad(bullet_arc)
			var increment = arc_rad / (bullet_count - 1)
			global_rotation = (
				0 +
				increment * i -
				arc_rad / 2
			)
			now_bullet.global_position = shoot_position.global_position
			now_bullet.global_rotation = global_rotation
			
			now_bullet.active_state()
			if add_bullet == true:
				get_tree().get_first_node_in_group("BulletRoot").call_deferred("add_child",now_bullet)
			SoundManager.call_deferred("play_sfx","GunSounds3")
			timer.start()
			await timer.timeout
	
	timer.wait_time = 1
	timer.start()
	await timer.timeout
	can_move.emit()
