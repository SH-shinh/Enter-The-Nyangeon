extends Node2D

@export var shoot_at_once:bool = true
@export var bullet_scale: float = 1
@export var bullet_count: int
@export_range(0, 360) var bullet_arc :float
@export var bullet: PackedScene
@export var bullet_damage: float
@export var convert_power: int = 0
@export var bullet_speed: float
@export var bullet_penetrate: int
@export var collision_num: int
@export var decay_time: float
@export var decay_speed: int
@export var kill_time: float
@export var explosion_range: float
@export var shoot_bullet_num: int
@export var shrapnel_random_speed: bool = false

var knockback_force: int = 0

var source_faction: int = Faction.ENEMY_SIDE

@export var bullet_id: String

@onready var shoot_position = $ShootPosition

func _ready():
	
	
	if shoot_at_once == true:
		shoot_bullet()

func shoot_bullet():
	if bullet_count == 1:
		ProjectileSpawner.spawn_core(
			bullet, bullet_id, "BulletRoot", _spawn_owner(), source_faction,
			shoot_position.global_position, global_rotation, Vector2(bullet_scale, bullet_scale),
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
				bullet, bullet_id, "BulletRoot", _spawn_owner(), source_faction,
				shoot_position.global_position, global_rotation + increment * i - arc_rad / 2, Vector2(bullet_scale, bullet_scale),
				false, false, true,
				Callable(self, "_configure_bullet"),
				Callable(),
				Callable(self, "_post_bullet")
			)

func _spawn_owner() -> Node:
	var p := get_parent()
	return p if p != null else self

func _configure_bullet(node: Node) -> void:
	node.damage_data = DamageData.fill(node.damage_data, {
		"damage": bullet_damage,
		"convert": convert_power,
		"knockback": knockback_force,
		"type": GameTags.BULLET_DAMAGE,
		"source": DamageRouter.source_tag(source_faction),
	})
	node.set("source_faction", source_faction)
	node.set("shrapnel_random_speed", shrapnel_random_speed)
	node.speed = bullet_speed
	node.penetrate = bullet_penetrate
	node.collision_num = collision_num
	node.decay_time = decay_time * 10
	node.decay_speed = decay_speed
	node.kill_time = kill_time * 10
	node.shoot_bullet_num = shoot_bullet_num
	if explosion_range > 0:
		node.explosion_range = explosion_range

func _post_bullet(node: Node) -> void:
	node.damage_data.source_node = node.get_path()
	
