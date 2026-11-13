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
## 分裂/子代是否按父子弹快照继承伤害（shrapnel_bullet 使用）。
var snapshot_damage: bool = false
var crosshair_pos: Vector2
var player: Node

# 玩家会在换角色时被销毁重建；取用前统一重新解析（见 PlayerRef）。
func _ensure_player() -> Node:
	player = PlayerRef.ensure(self, player)
	return player

var flags: Array[String]

func _ready():
	player = PlayerRef.resolve(self)
	if shoot_at_once == true:
		shoot_bullet()
	GameEvents.crosshair_position.connect(get_crosshair_pos)

func get_crosshair_pos(crosshair_position: Vector2):
	crosshair_pos = crosshair_position * get_canvas_transform()

func shoot_bullet():
	player = _ensure_player()
	if player == null:
		return
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
	player = _ensure_player()
	if player == null:
		return
	# 字段守卫：允许继承非标准 PlayerBullet 场景（缺字段时不报错）。
	if node.get("speed") != null:
		node.speed = bullet_speed
	if node.get("penetrate") != null:
		node.penetrate = bullet_penetrate
	if node.get("collision_num") != null:
		node.collision_num = collision_num
	if node.get("kill_time") != null:
		node.kill_time = player.stats.bullet_kill_time * 10
	if bullet_can_r == true and node.get("can_r") != null:
		node.can_r = true
		node.target_position = crosshair_pos

func _configure_bullet_multi(node: Node) -> void:
	if damage_data != null:
		node.damage_data = damage_data.duplicate(true)
		if node.damage_data != null:
			# 不继承父子弹的 on-hit 闭包，避免子代命中误改父子弹/重复触发。
			node.damage_data.on_damage_dealt.clear()
	_configure_bullet(node)

func _post_bullet(node: Node) -> void:
	player = _ensure_player()
	if player == null:
		return
	if !flags.is_empty():
		for i in flags:
			player.flags.append(i)
	GameEvents.emit_player_shot_position(shoot_position.global_position, node)
	# 快照继承：覆盖回父子弹的实际伤害/暴击与标签（emit 会按玩家当前 stats 重算 base）。
	if snapshot_damage and damage_data != null and node.get("damage_data") != null:
		var dd = node.damage_data
		dd.base_damage = damage_data.base_damage
		dd.is_crit = damage_data.is_crit
		for t in damage_data.damage_type:
			if not dd.damage_type.has(t):
				dd.damage_type.append(t)
		for t in damage_data.source_type:
			if not dd.source_type.has(t):
				dd.source_type.append(t)
