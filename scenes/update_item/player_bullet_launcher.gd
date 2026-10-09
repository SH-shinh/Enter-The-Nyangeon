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

var damage_data: DamageData
var crosshair_pos: Vector2
var player: Node

var flags: Array[String]

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	if shoot_at_once == true:
		shoot_bullet()
	GameEvents.crosshair_position.connect(get_crosshair_pos)

func get_crosshair_pos(crosshair_position: Vector2):
	crosshair_pos = crosshair_position * get_canvas_transform()

func shoot_bullet():
	if bullet_count == 1:
		var direction: Vector2 = global_position \
				.direction_to(crosshair_pos) \
				.normalized()
		shoot_position.rotation = direction.angle()
		ProjectileSpawner.spawn_core(
			bullet, pool_id, "BulletRoot", player, Faction.PLAYER_SIDE,
			shoot_position.global_position, global_rotation, Vector2.ZERO,
			false, false, true,
			Callable(self, "_configure_bullet"),
			Callable(),
			Callable(self, "_post_bullet")
		)
	else:
		var arc_rad = deg_to_rad(bullet_arc)
		var increment = arc_rad / (bullet_count - 1)
		for i in bullet_count:
			ProjectileSpawner.spawn_core(
				bullet, pool_id, "BulletRoot", player, Faction.PLAYER_SIDE,
				shoot_position.global_position, global_rotation + increment * i - arc_rad / 2, Vector2.ZERO,
				false, false, true,
				Callable(self, "_configure_bullet_multi"),
				Callable(),
				Callable(self, "_post_bullet")
			)
	flags.clear()
	
	if end_free == true:
		call_deferred("queue_free")

func _configure_bullet(node: Node) -> void:
	node.speed = bullet_speed
	node.penetrate = bullet_penetrate
	node.collision_num = collision_num
	node.kill_time = player.stats.bullet_kill_time * 10
	if bullet_can_r == true:
		node.can_r = true
		node.target_position = crosshair_pos

func _configure_bullet_multi(node: Node) -> void:
	if damage_data != null:
		node.damage_data = damage_data.duplicate(true)
	_configure_bullet(node)

func _post_bullet(node: Node) -> void:
	if !flags.is_empty():
		for i in flags:
			player.flags.append(i)
	GameEvents.emit_player_shot_position(shoot_position.global_position, node)
