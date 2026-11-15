extends EquipItem

# 圆盘碎片（Colgante Piece）：近战命中带恶寒的敌人 → 以敌人为中心发射冰片。
# 冰片按玩家子弹模板：速度为玩家子弹速度、存活固定 2 秒、吃穿透值；
# 伤害以触发的近战伤害为基础，吃异常伤害加成（dot_damage），类型为「恶寒 + 装备」。

const SHARD_SCENE: PackedScene = preload("res://scenes/bullet/frost_shard.tscn")
const BURST_SCENE: PackedScene = preload("res://scenes/effects/snowflake_burst.tscn")
const CHILL_ID: String = "chill_dot"
const CHILL_BUFF: Buff = preload("res://resources/buff/enemy_buff/chill_dot.tres")

## 按件数的伤害比例（触发近战伤害 × dot_damage × ratio）。
const RATIOS: Array[float] = [0.5, 0.6, 0.7]
## 初始冰片数，每多 1 件 +1。
const BASE_SHARDS: int = 3
## 每片命中施加的恶寒层数 / 时长。
const CHILL_PER_HIT: int = 1
const CHILL_DURATION: float = 3.0
## 本道具来源的恶寒层上限：初始 1，每多 1 件 +1。
const BASE_CHILL_CAP: int = 1
const TRIGGER_CD_MS: int = 350
## 冰片生成在敌人外侧的距离，避免立刻回头打源敌人。
const SPAWN_OFFSET: float = 26.0
## 冰片存活固定 2 秒（kill_time 由 10Hz 的 global_time_count 递减）。
const SHARD_KILL_TIME: int = 20
## 单次触发的冰片数上限（弹道数量乘上来后防止刷爆弹体池/特效）。
const MAX_SHARDS: int = 16

var _ratio: float = RATIOS[0]
var _shard_count: int = BASE_SHARDS
var _chill_cap: int = BASE_CHILL_CAP
var _next_trigger_ms: int = 0

func _setup() -> void:
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.enemy_damage_taken.connect(_on_enemy_damage_taken)
	GameEvents.player_bullet_hit_enemy.connect(_on_shard_hit)

func _apply_effect(quantity: int) -> void:
	var idx: int = clampi(quantity, 1, RATIOS.size()) - 1
	_ratio = RATIOS[idx]
	_shard_count = BASE_SHARDS + idx
	_chill_cap = BASE_CHILL_CAP + idx

## 冰片命中：给目标叠本道具来源的恶寒（到上限后只刷新时长）。
func _on_shard_hit(bullet: Node, victim: Node) -> void:
	if bullet == null or str(bullet.get("pool_id")) != "frost_shard":
		return
	if victim == null or not is_instance_valid(victim):
		return
	var manager = victim.get("enemy_buff_manager")
	if manager == null:
		return
	if victim.get("stats") != null and float(victim.stats.hp) <= 0.0:
		return
	for i in CHILL_PER_HIT:
		manager.apply_buff(CHILL_BUFF, [_chill_cap, 0.0, CHILL_DURATION], item_id)

func _on_enemy_damage_taken(final_damage: int, damage_data: DamageData, body_path: NodePath) -> void:
	if damage_data == null or not damage_data.damage_type.has(GameTags.MELEE_DAMAGE):
		return
	var now: int = Time.get_ticks_msec()
	if now < _next_trigger_ms:
		return
	var enemy: Node = get_node_or_null(body_path)
	if enemy == null or not is_instance_valid(enemy):
		return
	var manager = enemy.get("enemy_buff_manager")
	if manager == null:
		return
	var current = manager.get("current_buff")
	if not (current is Dictionary):
		return
	var chill = current.get(CHILL_ID)
	if not (chill is Dictionary) or bool(chill.get("stop", false)) or int(chill.get("layer", 0)) <= 0:
		return
	if player == null or player.get("stats") == null:
		return
	var stats = player.stats
	_next_trigger_ms = now + TRIGGER_CD_MS
	var damage: int = maxi(1, int(round(float(final_damage) * float(stats.dot_damage) * _ratio)))
	_spawn_shards(enemy, damage, stats)
	var burst := PoolManager.spawn_fx("snowflake_burst", BURST_SCENE, enemy)
	if burst != null:
		# 迸发特效走联机视觉广播（副本调 active_state 播放），与 kikyou/renge 同范式。
		ExtensionHooks.notify_named("on_visual_activated", [burst])
	SoundManager.play_sfx("IceSpell")

func _spawn_shards(enemy: Node, damage: int, stats) -> void:
	var base_angle: float = randf_range(0.0, TAU)
	# 吃玩家弹道数量加成：1 发保持基础片数，多弹道按倍数放大（有上限）。
	var shots: int = maxi(1, int(stats.bullet_count))
	var count: int = mini(_shard_count * shots, MAX_SHARDS)
	for i in count:
		var angle: float = base_angle + TAU * float(i) / float(count) + randf_range(-0.14, 0.14)
		var spawn_pos: Vector2 = enemy.global_position + Vector2.RIGHT.rotated(angle) * SPAWN_OFFSET
		ProjectileSpawner.spawn_core(
			SHARD_SCENE, "frost_shard", "BulletRoot", player, Faction.PLAYER_SIDE,
			spawn_pos, angle, Vector2.ONE * stats.bullet_scale,
			false, false, true,
			Callable(self, "_configure_shard").bind(damage, stats),
			Callable(),
			Callable(self, "_post_shard")
		)

## 入树前：只写字段（不能碰 @onready 子节点）。
func _configure_shard(node: Node, damage: int, stats) -> void:
	if node.get("speed") != null:
		node.speed = stats.bullet_speed
	if node.get("kill_time") != null:
		node.kill_time = SHARD_KILL_TIME
	if node.get("penetrate") != null:
		node.penetrate = stats.bullet_penetrate
	node.damage_data = DamageData.fill(null, {
		"damage": damage,
		"type": [GameTags.CHILL_DAMAGE, GameTags.EQUIP_DAMAGE],
		"source": GameTags.EQUIP,
		"node": node,
		"knockback": stats.bullet_knockback,
	})

## 入树后：接管穿透递减与命中通知（与玩家子弹同语义）。
func _post_shard(node: Node) -> void:
	if node.has_method("apply_penetrate_dealt"):
		node.apply_penetrate_dealt()
