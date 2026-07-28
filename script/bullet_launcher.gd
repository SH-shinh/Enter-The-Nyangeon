extends Node2D

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

var bullet_damage_mult: float = 1

@export var bullet_id: String

@onready var shoot_position = $ShootPosition

func _ready():
	
	
	if shoot_at_once == true:
		shoot_bullet()

func shoot_bullet():
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
		
		now_bullet.active_state()
		if add_bullet == true:
			get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
		
	
	else:
	
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
			now_bullet.global_position = shoot_position.global_position
			if explosion_range > 0:
				now_bullet.explosion_range = explosion_range
			
			var arc_rad = deg_to_rad(bullet_arc)
			var increment = arc_rad / (bullet_count - 1)
			now_bullet.global_rotation = (
				global_rotation +
				increment * i -
				arc_rad / 2
			)
			
			now_bullet.active_state()
			if add_bullet == true:
				get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
	
