extends EquipItem

# 黄瓜味牙膏：带毒的敌人死亡后，在尸体位置留下一滩毒池；池子持续给范围内的敌人叠毒。
# 毒值口径照桔梗人偶：按玩家子弹伤害比例计算（再乘装备伤害加成），不吃二次 dot_damage。

const POOL_SCENE: PackedScene = preload("res://scenes/update_item/poison_pool.tscn")
const POISON_ID: String = "poison_dot"

## 按件数的毒值比例（子弹伤害 × 装备伤害 × ratio）。
const RATIOS: Array[float] = [0.7, 1.0, 1.5]
## 触发内置冷却：防止同一帧/连环死亡刷出一片毒池。
const TRIGGER_CD_MS: int = 800
const POOL_CAP_BASE: int = 6
const POOL_CAP_STEP: int = 2
const MERGE_RADIUS: float = 32.0
## 与 poison_pool.tscn 的默认值保持一致（80 / 4.0）：复用时道具显式覆盖，
## 避免池子沿上一次被改过的值；联机广播参数也复用这两个常量。
const SELF_LIFE: int = 80
const POISON_DURATION: float = 4.0

var _pools: Array[Node] = []
var _pool_index: int = 0
var _ratio: float = RATIOS[0]
var _pool_cap: int = POOL_CAP_BASE
var _next_trigger_ms: int = 0

func _setup() -> void:
	GameEvents.enemy_damage_taken_dead.connect(_on_enemy_dead)

func _apply_effect(quantity: int) -> void:
	var idx: int = clampi(quantity, 1, RATIOS.size()) - 1
	_ratio = RATIOS[idx]
	_pool_cap = POOL_CAP_BASE + POOL_CAP_STEP * idx

func _on_enemy_dead(_final_damage: int, _damage_data: DamageData, body_path: NodePath) -> void:
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
	var poison = current.get(POISON_ID)
	if not (poison is Dictionary):
		return
	if bool(poison.get("stop", false)) or int(poison.get("layer", 0)) <= 0:
		return
	if player == null or player.get("stats") == null:
		return
	var stats = player.stats
	_next_trigger_ms = now + TRIGGER_CD_MS
	var value: float = maxf(1.0, roundf(float(stats.bullet_damage) * float(stats.equip_damage) * _ratio))
	_place_pool(enemy.global_position, value)

func _place_pool(pos: Vector2, value: float) -> void:
	var nearby := _find_nearby_pool(pos)
	if nearby != null:
		# 同点合并：续命 + 取较高毒值，不新建节点。
		nearby.poison_value = maxf(float(nearby.poison_value), value)
		nearby.refresh_field()
		_broadcast(nearby)
		return
	var pool := _get_pool()
	if pool == null:
		return
	pool.global_position = pos
	pool.self_life = SELF_LIFE
	pool.poison_value = value
	pool.poison_duration = POISON_DURATION
	pool.active_state()
	_broadcast(pool)

func _broadcast(pool: Node) -> void:
	ExtensionHooks.notify_named("on_visual_activated", [pool, {
		"self_life": SELF_LIFE,
		"poison_value": float(pool.poison_value),
		"poison_duration": POISON_DURATION,
	}])

func _find_nearby_pool(pos: Vector2) -> Node:
	for p in _pools:
		if p == null or not is_instance_valid(p) or p.is_idle == 1:
			continue
		if (p as Node2D).global_position.distance_to(pos) <= MERGE_RADIUS:
			return p
	return null

# 内部池：优先取空闲；满上限时循环复用最旧的并强制复位。
func _get_pool() -> Node:
	var alive: Array[Node] = []
	for p in _pools:
		if p == null or not is_instance_valid(p):
			continue
		if p.is_idle == 1:
			return p
		alive.append(p)
	_pools = alive
	if _pools.size() >= _pool_cap:
		var reused: Node = _pools[_pool_index % _pools.size()]
		_pool_index = (_pool_index + 1) % _pools.size()
		reused.idle_state()
		return reused
	var created := POOL_SCENE.instantiate()
	get_tree().get_first_node_in_group("SELayer").add_child(created)
	_pools.push_back(created)
	return created
