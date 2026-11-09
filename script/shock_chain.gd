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
## 链头没有搭档时的重试间隔（tick），避免孤立目标每 tick 全表扫描。
const SHOCK_RETRY_TICKS := 2

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


## 感电伤害免疫：目标实现 is_shock_immune()，或在其 stats 上置 shock_immune，即跳过伤害（仍可被链选中/传导）。
static func is_immune(body: Node) -> bool:
	if body == null or not is_instance_valid(body):
		return true
	if body.has_method("is_shock_immune") and bool(body.call("is_shock_immune")):
		return true
	var st = body.get("stats")
	if st == null:
		return false
	var v = st.get("shock_immune")
	return v != null and bool(v)


## 由 EnemyBuffManager._tick_shock_dot 调用：倒计时到点则尝试整条链。
static func tick(manager: Node, body: Node, entry: Dictionary) -> void:
	if body == null or not is_instance_valid(body):
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
	var path := _build_path(body, entry, manager)
	if path.size() < 2:
		# 孤立目标：不要每 tick 重扫全表，等下一个重试窗口。
		entry["shock_cd"] = SHOCK_RETRY_TICKS
		return
	_last_chain_ms = now
	# 先重置整条链的节拍并出表现；再按跳序结算；最后给仍存活的节点叠易伤
	# （本次命中不吃自己这层 5%，下一次链才吃）。
	for p in path:
		p["manager"].reset_shock_cd()
	_spawn_arc(path, int(entry["layer"]))
	for i in path.size():
		path[i]["manager"].shock_chain_hit(pow(HOP_DECAY, float(i)))
	for p in path:
		p["manager"].add_shock_vuln()
	# host 链已结算完（伤害 + 层数），交给 mod 广播 net_id 序列与每节点 vuln_stacks。
	ExtensionHooks.notify_named("on_shock_chain", [path, int(entry["layer"])])


## 客机回放 host 的链：重置节拍、同步易伤层数并出同一条 VFX，不结算伤害。
static func replay_remote(bodies: Array, power: int, stacks: Array) -> void:
	if bodies.size() < 2:
		return
	var path: Array = []
	for i in bodies.size():
		var b: Node = bodies[i]
		if b == null or not is_instance_valid(b):
			continue
		var m = b.get("enemy_buff_manager")
		if m == null:
			continue
		m.reset_shock_cd()
		m.network_set_shock_vuln(int(stacks[i]) if i < stacks.size() else 0)
		path.append({"body": b, "manager": m})
	if path.size() >= 2:
		_spawn_arc(path, power)


# 从链头贪心走链：每跳取最近的、未被访问过的感电目标，跳距受当前节点层数限制。
# 候选表一次建好，链段以 {body, manager, entry} 返回，后续循环不再重复查 manager。
static func _build_path(head: Node, head_entry: Dictionary, head_manager: Node) -> Array:
	var pool := _candidate_pool(head)
	var path: Array = [{"body": head, "manager": head_manager, "entry": head_entry}]
	var visited: Dictionary = {head.get_instance_id(): true}
	var current: Node = head
	var current_entry: Dictionary = head_entry
	var limit: int = hop_limit_for(int(head_entry["layer"]))
	while path.size() < limit:
		var next := _nearest_shocked(current, visited, pool)
		if next.is_empty():
			break
		if current.global_position.distance_to(next["body"].global_position) > range_for(int(current_entry["layer"])):
			break
		path.append(next)
		visited[next["body"].get_instance_id()] = true
		current = next["body"]
		current_entry = next["entry"]
	return path


# 一次链只建一次候选表，避免每跳重复 _entry_of / get("enemy_buff_manager")。
static func _candidate_pool(head: Node) -> Array:
	var pool: Array = []
	for e in Targeting.candidates():
		if e == null or not is_instance_valid(e) or e == head:
			continue
		if e.get("is_idle") == 1:
			continue
		var st = e.get("stats")
		if st != null and st.hp <= 0 and not bool(st.is_test_target):
			continue
		var m = e.get("enemy_buff_manager")
		if m == null:
			continue
		var entry := _entry_of(e)
		if entry.is_empty():
			continue
		pool.append({"body": e, "manager": m, "entry": entry})
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for comp in tree.get_nodes_in_group("ShockCarrier"):
			if comp == null or not is_instance_valid(comp):
				continue
			var b: Node = comp.get("body")
			if b == null or not is_instance_valid(b) or b == head:
				continue
			if b.get("is_idle") == 1 or b.get("is_downed") == true:
				continue
			var bst = b.get("stats")
			if bst == null:
				continue
			var bmax = bst.get("max_hp")
			var bhp = bst.get("hp")
			if bmax == null or int(bmax) <= 0 or bhp == null or int(bhp) <= 0:
				continue
			var bhc = b.get("health_component")
			if bhc != null and bhc.get("can_hurt") == false:
				continue
			var centry = comp.call("get_shock_entry")
			if not (centry is Dictionary) or centry.is_empty():
				continue
			if bool(centry.get("stop", false)) or int(centry.get("layer", 0)) <= 0:
				continue
			pool.append({"body": b, "manager": comp, "entry": centry})
	return pool


# 最近的、未被本链访问过的感电目标；找不到返回空字典。
static func _nearest_shocked(from: Node, visited: Dictionary, pool: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = INF
	for c in pool:
		var e: Node = c["body"]
		if visited.has(e.get_instance_id()):
			continue
		var d: float = from.global_position.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = c
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
	var fx = PoolManager.get_pool(FX_POOL)
	if fx == null or fx.is_idle == 0:
		fx = ARC_SCENE.instantiate()
		layer.add_child(fx)
	var points: Array[Vector2] = []
	for p in path:
		var node: Node = p["body"]
		if node == null or not is_instance_valid(node):
			continue
		points.append((node as Node2D).global_position + Vector2(0, -12))
	fx.play(points, power)
