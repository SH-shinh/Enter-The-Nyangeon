extends Node

## 金币掉落/合并管理器（autoload `CoinManager`）。
## 金币池上限 COIN_POOL_CAP；满额时新掉落并入最近的活跃金币，不新建节点。
## 活跃金币由 `scenes/item/coin.gd` 在 `active_state()`/`idle_state()`/`_exit_tree()`
## 登记/注销，本类为唯一活跃集真源（仿 `PoolManager._active_enemies`）。

const COIN_POOL_CAP: int = 150
# 惰性加载：coin.gd 引用 autoload `CoinManager`，顶层 preload coin.tscn 会形成
# autoload ↔ preload 循环（清缓存冷启动可能报 Identifier not found: CoinManager）。
const COIN_SCENE_PATH: String = "res://scenes/item/coin.tscn"
var _coin_scene: PackedScene = null

var _active: Dictionary = {}   # instance_id -> coin
var active_count: int = 0

# 青辉石拾取后置真：本回合内所有金币（含之后才生成的）自动飞向玩家
var auto_pick: bool = false

func _ready() -> void:
	GameEvents.pyroxenes_pick_up.connect(_on_pyroxenes_pick_up)
	GameEvents.round_start.connect(_on_round_start)

func _on_pyroxenes_pick_up() -> void:
	auto_pick = true
	_prune_active()
	for c in _active.values():
		if c != null and is_instance_valid(c) and c.is_idle == 0:
			c.auto_pick()

func _on_round_start() -> void:
	auto_pick = false

func register(coin: Node) -> void:
	if coin == null or not is_instance_valid(coin):
		return
	var id := coin.get_instance_id()
	if _active.has(id):
		return
	_active[id] = coin
	active_count = _active.size()

func unregister(coin: Node) -> void:
	if coin == null:
		return
	if _active.erase(coin.get_instance_id()):
		active_count = _active.size()

# 剔除失效 / 已回池的登记项（兜底任何漏报的注销）
func _prune_active() -> void:
	if _active.is_empty():
		return
	var dirty := false
	for id in _active.keys():
		var c = _active[id]
		if c == null or not is_instance_valid(c) or c.is_idle == 1:
			_active.erase(id)
			dirty = true
	if dirty:
		active_count = _active.size()

## 统一掉落入口：优先复用空闲金币；未满额则新建；满额并入最近的活跃金币。
func drop_coin(pos: Vector2, value: int, pick_up: bool) -> void:
	if value <= 0:
		return
	var root := _coin_root()
	if root == null:
		return

	var c = PoolManager.get_pool_idle("coins")
	if c != null:
		_activate(c, pos, value, pick_up)
		return

	if active_count < COIN_POOL_CAP:
		c = _get_coin_scene().instantiate()
		root.add_child(c)
		_activate(c, pos, value, pick_up)
		return

	# 满额：并入最近的一枚。优先可拾取的金币，避免并入仍抛物飞行/Boss 演出金币（回合末不返还）。
	var target = _nearest_active(pos, true)
	if target == null:
		target = _nearest_active(pos, false)
	if target != null:
		target.absorb(value, pick_up)
		return

	# 兜底：无任何活跃金币可并入（理论上不会发生），仍新建以免丢值。
	c = _get_coin_scene().instantiate()
	root.add_child(c)
	_activate(c, pos, value, pick_up)

func _get_coin_scene() -> PackedScene:
	if _coin_scene == null:
		_coin_scene = load(COIN_SCENE_PATH)
	return _coin_scene

func _activate(c: Node, pos: Vector2, value: int, pick_up: bool) -> void:
	c.global_position = pos
	c.coin = value
	c.pick_up = pick_up
	c.active_state()

func _nearest_active(pos: Vector2, require_pickable: bool) -> Node:
	_prune_active()
	var best: Node = null
	var best_d := INF
	for c in _active.values():
		if c == null or not is_instance_valid(c) or c.is_idle == 1:
			continue
		if require_pickable and c.can_pick == false:
			continue
		var d: float = c.global_position.distance_squared_to(pos)
		if d < best_d:
			best_d = d
			best = c
	return best

func _coin_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("CoinRoot")
