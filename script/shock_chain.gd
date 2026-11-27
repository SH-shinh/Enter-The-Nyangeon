class_name ShockChain
## 感电（shock_dot）的单链跳转结算入口。
##
## 一次放电只产生一条链：从链头出发，逐跳连到最近的、尚未被本链命中的感电目标；
## 链上每个节点按自身层数结算一次感电伤害，并叠加一层「感电易伤」。
## 结算由各敌人的 EnemyBuffManager 在 10Hz tick 驱动，本类只做静态协调。
##
## 触发频率：**伤害侧没有全局单链上限**——同一 tick 内每个 `shock_cd` 到点的链头各自出一条链
## （场上感电目标越多，链越多）。上限只作用于**视觉**：`_spawn_arc` 受
## `PoolManager.fx_allowed("shock_chain", 80ms)` 与电弧池上限限制，电弧数量不随链数量线性增长。
## 多条链在同一帧结算时靠条目上的 `chain_frame`（= `Engine.get_process_frames()`）去重：
## 同一帧每个目标最多被一条链命中一次，否则 N 条链 × 6 跳会把同一个目标单帧打 6N 次。

const SHOCK_DOT_ID := "shock_dot"
## 玩家侧感电（挂在玩家/召唤物身上的 shock 类 Buff）的层数硬上限。
## 用户裁定（2026-11-14）：玩家侧叠层不受 `stats.shock_layer` 限制，最高 999 层；
## 该上限由 PlayerBuffManager 在创建条目时统一覆盖，施加方传进来的 value[0] 不参与。
## 注意：敌人身上的感电仍由施加者的 `stats.shock_layer` 管，两边不再共用同一个上限。
const PLAYER_SHOCK_MAX_LAYERS: int = 999
const HOP_DECAY := 0.85
const HOP_MAX := 6
const RANGE_BASE := 96.0
const RANGE_STEP := 20.0
const INTERVAL_TICKS_BASE := 12
const INTERVAL_TICKS_STEP := 2
const INTERVAL_TICKS_MIN := 4
## 链头没有搭档时的重试间隔（tick），避免孤立目标每 tick 全表扫描。
const SHOCK_RETRY_TICKS := 2

const ARC_SCENE: PackedScene = preload("res://scenes/debuff/shock_chain_arc.tscn")
const FX_POOL := "shock_chain"
const FX_CATEGORY := &"shock_chain"


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
## 多个管理器会在同一帧各自调用本函数（同一 10Hz tick），互不阻塞：各自建链、各自结算。
static func tick(manager: Node, body: Node, entry: Dictionary) -> void:
	if body == null or not is_instance_valid(body):
		return
	if bool(entry.get("stop", false)) or int(entry.get("layer", 0)) <= 0:
		return
	var cd: int = int(entry.get("shock_cd", 0)) - 1
	entry["shock_cd"] = maxi(0, cd)
	if cd > 0:
		return
	# 同一帧的链共用一个帧标记：同 tick 的所有管理器都在同一个 process 帧内同步执行，
	# 跨 tick 至少相隔 100ms。用帧号而不是 msec——一帧内多条链结算耗时就会跨毫秒。
	var frame: int = Engine.get_process_frames()
	var path := _build_path(body, entry, manager, frame)
	if path.size() < 2:
		# 孤立目标：不要每 tick 重扫全表，等下一个重试窗口。
		entry["shock_cd"] = SHOCK_RETRY_TICKS
		return
	# 先打帧标记 + 重置整条链的节拍并出表现；再按跳序结算；最后给仍存活的节点叠易伤
	# （本次命中不吃自己这层 5%，下一次链才吃）。
	# 帧标记让同帧后续的链跳过这些目标：每个目标每帧最多结算一次。
	var chain_dir := Vector2.ZERO
	if path.size() >= 2:
		chain_dir = (path[path.size() - 1]["body"].global_position - path[0]["body"].global_position).normalized()
	for p in path:
		var e: Dictionary = p["entry"]
		e["chain_frame"] = frame
		p["manager"].reset_shock_cd()
	_spawn_arc(path, int(entry["layer"]))
	for i in path.size():
		path[i]["manager"].shock_chain_hit(pow(HOP_DECAY, float(i)), chain_dir)
	for p in path:
		p["manager"].add_shock_vuln()
	# host 链已结算完（伤害 + 层数），交给 mod 广播节点 ref、每节点 vuln_stacks 与链方向。
	ExtensionHooks.notify_named("on_shock_chain", [path, int(entry["layer"]), chain_dir])


## 客机回放 host 的链：重置节拍、同步易伤层数并出同一条 VFX；
## 只有 local_mask[i] 为真的本机玩家/召唤物节点才结算 2% + 击退（伤害归属 owner），
## host 的远端镜像只当链节点，不重复扣血/推人。
static func replay_remote(bodies: Array, power: int, stacks: Array, dir: Vector2 = Vector2.ZERO, local_mask: Array = []) -> void:
	if bodies.size() < 2:
		return
	var path: Array = []
	for i in bodies.size():
		var b: Node = bodies[i]
		if b == null or not is_instance_valid(b):
			continue
		var m := _manager_for(b)
		if m == null:
			continue
		m.reset_shock_cd()
		if m.has_method("network_set_shock_vuln"):
			m.network_set_shock_vuln(int(stacks[i]) if i < stacks.size() else 0)
		if i < local_mask.size() and bool(local_mask[i]):
			if m.has_method("replay_shock_hit"):
				m.call("replay_shock_hit", dir)
			elif m.has_method("shock_chain_hit"):
				m.call("shock_chain_hit", 1.0, dir)
		path.append({"body": b, "manager": m})
	if path.size() >= 2:
		_spawn_arc(path, power)


## 链节点的结算入口：敌人用 EnemyBuffManager，玩家/召唤物用 ShockCarrier 组件。
static func _manager_for(body: Node) -> Node:
	var m = body.get("enemy_buff_manager")
	if m != null:
		return m
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for comp in tree.get_nodes_in_group("ShockCarrier"):
		if comp != null and is_instance_valid(comp) and comp.get("body") == body:
			return comp
	return null


# 从链头贪心走链：每跳取最近的、未被访问过的感电目标，跳距受当前节点层数限制。
# 候选表一次建好，链段以 {body, manager, entry} 返回，后续循环不再重复查 manager。
# frame >= 0 时跳过本帧已被其它链命中的目标（同帧去重）。
static func _build_path(head: Node, head_entry: Dictionary, head_manager: Node, frame: int = -1) -> Array:
	var pool := _candidate_pool(head, frame)
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


# 本帧基础候选表缓存（frame >= 0 的真实运行路径）：
# 同一 tick 内 N 条链原本各自重建一次全表（105 敌 × 7 条链实测 ≈0.57ms/帧），
# 现在一帧只建一次，链之间只做 O(1) 资格过滤。
static var _pool_frame: int = -1
static var _pool_base: Array = []

# 候选表：frame >= 0 时按帧复用基础池；链之间只重校验「本帧已被别的链命中 / 条目失效 / 已回池 / 已死」。
static func _candidate_pool(head: Node, frame: int = -1) -> Array:
	if frame >= 0 and frame == _pool_frame:
		return _filter_pool(_pool_base, head, frame)
	var pool := _build_pool_base()
	if frame >= 0:
		_pool_frame = frame
		_pool_base = pool
	return _filter_pool(pool, head, frame)


static func _filter_pool(base: Array, head: Node, frame: int) -> Array:
	var pool: Array = []
	var head_id: int = head.get_instance_id()
	for c in base:
		var e: Node = c["body"]
		if e == null or not is_instance_valid(e) or e.get_instance_id() == head_id:
			continue
		var entry: Dictionary = c["entry"]
		if bool(entry.get("stop", false)) or int(entry.get("layer", 0)) <= 0:
			continue
		if frame >= 0 and int(entry.get("chain_frame", -1)) == frame:
			continue
		if e.get("is_idle") == 1:
			continue
		var st = e.get("stats")
		if st != null and st.hp <= 0 and not bool(st.is_test_target):
			continue
		pool.append(c)
	return pool


# 建一次「全部合法感电目标」基础表（不含链头过滤：每条链的链头不同）。
static func _build_pool_base() -> Array:
	var pool: Array = []
	for e in Targeting.candidates():
		if e == null or not is_instance_valid(e):
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
			if b == null or not is_instance_valid(b):
				continue
			if b.get("is_idle") == 1 or b.get("is_downed") == true:
				continue
			# 感电导管（如 Chihiro 无人机）：没有 stats/health_component 也允许进链；
			# 链命中时由导管组件自行忽略伤害（shock_chain_hit 空实现）。
			# ⚠️ 组件不一定有这个属性（player_shock_component 就没有）：不能用 bool(x) 包 null，
			# 否则报「Nonexistent 'bool' constructor」把游戏打断。
			var conduit: bool = comp.get("shock_conduit") == true
			if not conduit:
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


## 电弧表现：**只在这里**做全局节流（每条链都会调用，但同一帧/同一窗口只有第一条真正出图）。
## 伤害结算不走这个门——场上感电目标再多，链数量也照常结算，只有可见电弧数量受限。
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
