class_name Targeting

# 选敌工具：以 PoolManager.get_active_enemies()（活跃敌人注册表，由敌人实体
# active_state/idle_state/_exit_tree 维护，天然排除 EnemyPart）为准，
# 过滤对象池待机与已策反单位；若为空则回退遍历 "Enemy" 组（同样过滤）。
#
# 候选列表按物理帧缓存：同一帧内多颗子弹共享同一份列表（省掉重复过滤与分配），
# 但每颗子弹仍以自己的位置独立选最近目标。

static var _cached_enemies: Array = []
static var _cached_frame: int = -1

static func _valid_enemy(e: Node) -> bool:
	if e == null or not is_instance_valid(e):
		return false
	if e.get("is_idle") != null and e.is_idle == 1:
		return false
	if e.get("faction") != null and e.faction == Faction.PLAYER_SIDE:
		return false
	return true

static func candidates() -> Array:
	var frame := Engine.get_physics_frames()
	if frame == _cached_frame:
		return _cached_enemies
	var out: Array = []
	if PoolManager != null:
		for e in PoolManager.get_active_enemies():
			if _valid_enemy(e):
				out.append(e)
	if out.is_empty():
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			for e in tree.get_nodes_in_group("Enemy"):
				if _valid_enemy(e):
					out.append(e)
	_cached_enemies = out
	_cached_frame = frame
	return _cached_enemies

static func nearest_enemy(from: Vector2) -> Node:
	var best: Node = null
	var best_d: float = INF
	for e in candidates():
		if e == null or not is_instance_valid(e):
			continue
		var d: float = from.distance_squared_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

static func enemies_sorted_by_distance(from: Vector2) -> Array:
	var arr: Array = []
	var distances := {}
	for enemy in candidates():
		if is_instance_valid(enemy):
			arr.append(enemy)
			distances[enemy] = from.distance_squared_to(enemy.global_position)
	arr.sort_custom(func(a, b): return distances[a] < distances[b])
	return arr

# 光束每个物理帧只需要最近的几个目标；缓存列表仍可供同帧其他武器共用。
static func nearest_enemies(from: Vector2, limit: int) -> Array:
	if limit <= 0:
		return []
	var nearest: Array = []
	var distances := PackedFloat64Array()
	for enemy in candidates():
		if not is_instance_valid(enemy):
			continue
		var d := from.distance_squared_to(enemy.global_position)
		if not is_finite(d):
			return enemies_sorted_by_distance(from).slice(0, limit)
		if nearest.size() == limit and d > distances[-1]:
			continue
		var i := distances.bsearch(d)
		# 并列可能影响光束的连线顺序或末位取舍，沿用原排序对同距目标的处理。
		if i < distances.size() and distances[i] == d:
			return enemies_sorted_by_distance(from).slice(0, limit)
		distances.insert(i, d)
		nearest.insert(i, enemy)
		if nearest.size() > limit:
			distances.resize(limit)
			nearest.pop_back()
	return nearest
