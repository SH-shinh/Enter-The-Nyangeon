extends Node2D

@export var shoot_at_once:bool = true
@export var pool_id: String = "player_bullet"
@export var end_free: bool = true
@export var bullet: PackedScene
@export var bullet_count: int
@export_range(0, 360) var bullet_arc :float
@export var bullet_speed: float
@export var bullet_penetrate: int
@export var collision_num: int
@export var bullet_can_r: bool = false

@onready var shoot_position = $ShootPosition

var crosshair_pos: Vector2
var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	if shoot_at_once == true:
		shoot_bullet()
	GameEvents.crosshair_position.connect(get_crosshair_pos)

func get_crosshair_pos(crosshair_position: Vector2):
	crosshair_pos = crosshair_position * get_canvas_transform()

func shoot_bullet():
	if bullet_count == 1:
		var now_bullet = PoolManager.get_pool(pool_id)
		var add_bullet: bool = false
		if now_bullet == null or now_bullet.is_idle == 0:
			now_bullet = bullet.instantiate()
			add_bullet = true
		
		var direction: Vector2 = global_position \
				.direction_to(crosshair_pos) \
				.normalized()
		now_bullet.speed = bullet_speed
		now_bullet.penetrate = bullet_penetrate
		now_bullet.collision_num = collision_num
		now_bullet.kill_time = player.stats.bullet_kill_time * 10
		now_bullet.position = shoot_position.global_position
		now_bullet.global_rotation = global_rotation
		shoot_position.rotation = direction.angle()
		if bullet_can_r == true:
			now_bullet.can_r = true
			now_bullet.target_position = crosshair_pos
		now_bullet.active_state()
		if add_bullet == true:
			get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
		GameEvents.emit_player_shot_position(shoot_position.global_position,now_bullet)
	
	else:
		var direction: Vector2 = global_position \
			.direction_to(crosshair_pos) \
			.normalized()
		
		for i in bullet_count:
			var now_bullet = PoolManager.get_pool(pool_id)
			var add_bullet: bool = false
			if now_bullet == null or now_bullet.is_idle == 0:
				now_bullet = bullet.instantiate()
				add_bullet = true
			now_bullet.speed = bullet_speed
			now_bullet.penetrate = bullet_penetrate
			now_bullet.collision_num = collision_num
			now_bullet.kill_time = player.stats.bullet_kill_time * 10
			now_bullet.position = shoot_position.global_position
			
			var arc_rad = deg_to_rad(bullet_arc)
			var increment = arc_rad / (bullet_count - 1)
			now_bullet.global_rotation = (
				global_rotation +
				increment * i -
				arc_rad / 2
			)
			if bullet_can_r == true:
				now_bullet.can_r = true
				now_bullet.target_position = crosshair_pos
			now_bullet.active_state()
			if add_bullet == true:
				get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
			GameEvents.emit_player_shot_position(shoot_position.global_position,now_bullet)
	if end_free == true:
		call_deferred("queue_free")
