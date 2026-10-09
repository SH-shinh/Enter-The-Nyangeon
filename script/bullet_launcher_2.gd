extends Node2D

signal can_move

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
@export var offset: float = 0
@export var offset_x: float = 0
@export var delay_time: float = 0.1
@export var bullet_id: String
var bullet_damage_mult: float = 1

var knockback_force: int = 0

var source_faction: int = Faction.ENEMY_SIDE
var move_released: bool = false

var burst_token: int = 0
var firing_stopped: bool = false

@onready var shoot_position = $ShootPosition
@onready var timer = $Timer

func begin_burst() -> int:
	firing_stopped = false
	burst_token += 1
	return burst_token

func burst_alive(tok: int) -> bool:
	return tok == burst_token

func stop_firing():
	burst_token += 1
	firing_stopped = true
	if timer != null:
		timer.stop()

func _ready():
	shoot_position.position.x = offset_x + offset
	if shoot_at_once == true:
		shoot_bullet()

func emit_can_move():
	move_released = true
	can_move.emit()

func _add_bullet_and_set_source(bullet: Node) -> void:
	get_tree().get_first_node_in_group("BulletRoot").add_child(bullet)
	bullet.damage_data.source_node = bullet.get_path()

func shoot_bullet():
	#var first_r = global_rotation
	
	timer.wait_time = delay_time
	move_released = false
	var tok := begin_burst()
	
	if bullet_count == 1:
		ProjectileSpawner.spawn_core(
			bullet, bullet_id, "BulletRoot", _spawn_owner(), source_faction,
			shoot_position.global_position, global_rotation, Vector2(bullet_scale, bullet_scale),
			false, false, true,
			Callable(self, "_configure_single"),
			Callable(),
			Callable(self, "_post_bullet")
		)
	else:
		var arc_rad = deg_to_rad(bullet_arc)
		var increment = arc_rad / (bullet_count - 1)
		for i in bullet_count:
			global_rotation = (
				0 +
				increment * i -
				arc_rad / 2
			)
			ProjectileSpawner.spawn_core(
				bullet, bullet_id, "BulletRoot", _spawn_owner(), source_faction,
				shoot_position.global_position, global_rotation, Vector2(bullet_scale, bullet_scale),
				false, true, true,
				Callable(self, "_configure_multi"),
				Callable(),
				Callable(self, "_post_bullet")
			)
			SoundManager.call_deferred("play_sfx","GunSounds3")
			timer.start()
			await timer.timeout
			if not burst_alive(tok):
				return
	
	timer.wait_time = 1
	timer.start()
	await timer.timeout
	if not burst_alive(tok):
		return
	emit_can_move()

func _spawn_owner() -> Node:
	var p := get_parent()
	return p if p != null else self

func _configure_single(node: Node) -> void:
	node.damage_data = DamageData.fill(node.damage_data, {
		"damage": bullet_damage,
		"convert": convert_power,
		"knockback": knockback_force,
		"type": GameTags.BULLET_DAMAGE,
		"source": DamageRouter.source_tag(source_faction),
	})
	node.set("source_faction", source_faction)
	node.speed = bullet_speed
	node.penetrate = bullet_penetrate
	node.collision_num = collision_num
	node.decay_time = decay_time * 10
	node.decay_speed = decay_speed
	node.kill_time = kill_time * 10
	node.shoot_bullet_num = shoot_bullet_num
	if explosion_range > 0:
		node.explosion_range = explosion_range
	can_move.connect(node.is_stop_false)
	if move_released:
		node.is_stop_false()

func _configure_multi(node: Node) -> void:
	node.damage_data = DamageData.fill(node.damage_data, {
		"damage": bullet_damage,
		"convert": convert_power,
		"knockback": knockback_force,
		"type": GameTags.BULLET_DAMAGE,
		"source": DamageRouter.source_tag(source_faction),
	})
	node.set("source_faction", source_faction)
	node.speed = bullet_speed
	node.penetrate = bullet_penetrate
	node.collision_num = collision_num
	node.decay_time = decay_time * 10
	node.decay_speed = decay_speed
	node.kill_time = kill_time * 10
	node.shoot_bullet_num = shoot_bullet_num
	node.is_stop = true
	if !can_move.is_connected(node.is_stop_false):
		can_move.connect(node.is_stop_false)
	if move_released:
		node.is_stop_false()
	if explosion_range > 0:
		node.explosion_range = explosion_range

func _post_bullet(node: Node) -> void:
	node.damage_data.source_node = node.get_path()
