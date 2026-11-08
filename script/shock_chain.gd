class_name ShockChain
## 感电（shock_dot）的单链跳转结算入口。
##
## 一次放电只产生一条链：从链头出发，逐跳连到最近的、尚未被本链命中的感电目标；
## 链上每个节点按自身层数结算一次感电伤害，并叠加一层「感电易伤」。
## 结算由各敌人的 EnemyBuffManager 在 10Hz tick 驱动，本类只做静态协调。

const SHOCK_DOT_ID := "shock_dot"
const HOP_DECAY := 0.85
const HOP_MAX := 6
const RANGE_BASE := 96.0
const RANGE_STEP := 20.0
const INTERVAL_TICKS_BASE := 12
const INTERVAL_TICKS_STEP := 2
const INTERVAL_TICKS_MIN := 4
## 同一时刻只允许一条链：两次放电的最小间隔（毫秒）。
const GLOBAL_GAP_MS := 90

const ARC_SCENE: PackedScene = preload("res://scenes/debuff/shock_chain_arc.tscn")
const FX_POOL := "shock_chain"
const FX_CATEGORY := &"shock_chain"

static var _last_chain_ms: int = -1000000


static func range_for(layer: int) -> float:
	return RANGE_BASE + RANGE_STEP * float(maxi(layer, 1) - 1)


static func interval_ticks_for(layer: int) -> int:
	return maxi(INTERVAL_TICKS_MIN, INTERVAL_TICKS_BASE - INTERVAL_TICKS_STEP * (maxi(layer, 1) - 1))


static func hop_limit_for(layer: int) -> int:
	return mini(HOP_MAX, 1 + maxi(layer, 1))


## 由 EnemyBuffManager._tick_shock_dot 调用：倒计时到点则尝试整条链。
static func tick(manager: Node, body: Node, entry: Dictionary) -> void:
	if body == null or not is_instance_valid(body) or entry == null:
		return
	if bool(entry.get("stop", false)) or int(entry.get("layer", 0)) <= 0:
		return
	var cd: int = int(entry.get("shock_cd", 0)) - 1
	entry["shock_cd"] = maxi(0, cd)
	if cd > 0:
		return
	var now := Time.get_ticks_msec()
	if now - _last_chain_ms < GLOBAL_GAP_MS:
		return
	var path := _build_path(body, entry)
	if path.size() < 2:
		return
	_last_chain_ms = now
	# 先叠易伤并重置整条链的节拍（两端都执行），再做表现与伤害。
	for node in path:
		var m = node.get("enemy_buff_manager")
		if m == null:
			continue
		m.add_shock_vuln()
		m.reset_shock_cd()
	_spawn_arc(path, int(entry["layer"]))
	for i in path.size():
		var m = path[i].get("enemy_buff_manager")
		if m != null:
			m.shock_chain_hit(pow(HOP_DECAY, float(i)))


# 从链头贪心走链：每跳取最近的、未被访问过的感电目标，跳距受当前节点层数限制。
static func _build_path(head: Node, head_entry: Dictionary) -> Array:
	var path: Array = [head]
	var visited: Dictionary = {head.get_instance_id(): true}
	var current: Node = head
	var current_layer: int = int(head_entry["layer"])
	var limit: int = hop_limit_for(current_layer)
	while path.size() < limit:
		var next := _nearest_shocked(current, visited)
		if next == null:
			break
		if current.global_position.distance_to(next.global_position) > range_for(current_layer):
			break
		var next_entry := _entry_of(next)
		if next_entry.is_empty():
			break
		path.append(next)
		visited[next.get_instance_id()] = true
		current = next
		current_layer = int(next_entry["layer"])
	return path


# 最近的、未被本链访问过的感电目标；找不到返回 null。
static func _nearest_shocked(from: Node, visited: Dictionary) -> Node:
	var best: Node = null
	var best_d: float = INF
	for e in Targeting.candidates():
		if e == null or not is_instance_valid(e):
			continue
		if e == from or visited.has(e.get_instance_id()):
			continue
		if e.get("is_idle") == 1:
			continue
		var st = e.get("stats")
		if st != null and st.hp <= 0 and not bool(st.is_test_target):
			continue
		if _entry_of(e).is_empty():
			continue
		var d: float = from.global_position.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


# 取目标的感电条目；无效/已移除返回空字典。
static func _entry_of(body: Node) -> Dictionary:
	var m = body.get("enemy_buff_manager")
	if m == null:
		return {}
	var entry = m.current_buff.get(SHOCK_DOT_ID)
	if entry == null or bool(entry.get("stop", false)) or int(entry.get("layer", 0)) <= 0:
		return {}
	return entry


static func _spawn_arc(path: Array, power: int) -> void:
	if not PoolManager.fx_allowed(FX_CATEGORY, 80):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var layer := tree.get_first_node_in_group("SELayer")
	if layer == null:
		return
	if not ARC_SCENE.can_instantiate():
		return
	var fx = PoolManager.get_pool(FX_POOL)
	if fx == null or fx.is_idle == 0:
		fx = ARC_SCENE.instantiate()
		layer.add_child(fx)
		if fx == null:
			return
	var points: Array[Vector2] = []
	for node in path:
		if node == null or not is_instance_valid(node):
			continue
		points.append((node as Node2D).global_position + Vector2(0, -12))
	if points.size() < 2:
		return
	fx.play(points, power)
