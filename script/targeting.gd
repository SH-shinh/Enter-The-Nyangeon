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
	var arr := candidates().duplicate()
	arr.sort_custom(func(a, b):
		return from.distance_squared_to(a.global_position) < from.distance_squared_to(b.global_position)
	)
	return arr
