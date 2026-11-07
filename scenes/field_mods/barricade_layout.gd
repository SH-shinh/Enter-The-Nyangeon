class_name BarricadeLayout
extends RefCounted

## 壁垒模板的纯格子图算法。
## 不依赖 MapChunks / PoolManager / get_tree()，运行时与模板编辑器共用。
##
## 格坐标来自主地图 TileMap（64x32 等距 tile，视觉上是菱形），不是世界坐标正方形网格。
## 4 邻接与 EnemyNavField 的 NEIGHBORS8 + 对角侧检查连通块等价：
## 斜步要求两侧正交格都可通行，因此必然存在一条 4 邻接绕行路径；8 邻域只影响流向/路径长度。
##
## 可通行判定（2026-11-06 用户裁定）：
##   实心墙体格不可通行；其余可行走格只按 4 邻接判断是否连通。
##   不使用 body-safe / clearance / 8 邻域 / 窄缝扩宽（2026-11-06 用户裁定）。

const INVALID_CELL := Vector2i(2147483647, 2147483647)
const NEIGHBOR_OFFSETS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]


# ---------------- 避让（建墙时） ----------------

## 从 wall_set 删除避让区内的格，返回 {counts:{...}, removed:{cell:reason}}。
## ctx:
##   player_position / player_cell / has_player / avoid_player_radius
##   center_position / has_center / avoid_center_radius
##   defer_boss_avoidance / boss_positions
##   portal_cells / portal_anchors / avoid_portal_radius
##   enemy_positions / avoid_enemy_radius
##   summoned_positions / avoid_summon_radius
##   reserved_cells
static func carve_out(wall_set: Dictionary, world_of: Callable, ctx: Dictionary) -> Dictionary:
	var counts := {
		"reserved": 0,
		"player": 0,
		"boss": 0,
		"center": 0,
		"portal": 0,
		"enemy": 0,
		"summoned": 0,
	}
	var removed: Dictionary = {}
	var player_position: Vector2 = ctx.get("player_position", Vector2.ZERO)
	var player_cell: Vector2i = ctx.get("player_cell", INVALID_CELL)
	var has_player: bool = bool(ctx.get("has_player", true))
	var player_radius: float = float(ctx.get("avoid_player_radius", 0.0))
	var center_position: Vector2 = ctx.get("center_position", Vector2.ZERO)
	var has_center: bool = bool(ctx.get("has_center", false))
	var center_radius: float = float(ctx.get("avoid_center_radius", 0.0))
	var defer_boss: bool = bool(ctx.get("defer_boss_avoidance", false))
	var portal_cells: Dictionary = ctx.get("portal_cells", {})
	var portal_anchors: Array = ctx.get("portal_anchors", [])
	var portal_radius: float = float(ctx.get("avoid_portal_radius", 0.0))
	var enemy_positions: Array = ctx.get("enemy_positions", [])
	var enemy_radius: float = float(ctx.get("avoid_enemy_radius", 0.0))
	var summoned_positions: Array = ctx.get("summoned_positions", [])
	var summon_radius: float = float(ctx.get("avoid_summon_radius", 0.0))
	var boss_positions: Array = ctx.get("boss_positions", [])
	var reserved_cells: Dictionary = ctx.get("reserved_cells", {})

	for cell in wall_set.keys():
		if not (cell is Vector2i):
			continue
		var world: Vector2 = world_of.call(cell)
		var reason := ""
		if reserved_cells.has(cell):
			reason = "reserved"
		elif has_player and (cell == player_cell or world.distance_to(player_position) < player_radius):
			reason = "player"
		elif _within_any(world, boss_positions, center_radius):
			reason = "boss"
		elif not defer_boss and has_center and world.distance_to(center_position) < center_radius:
			reason = "center"
		elif portal_cells.has(cell) or _within_any(world, portal_anchors, portal_radius):
			reason = "portal"
		elif _within_any(world, enemy_positions, enemy_radius):
			reason = "enemy"
		elif _within_any(world, summoned_positions, summon_radius):
			reason = "summoned"
		if reason != "":
			counts[reason] = int(counts[reason]) + 1
			removed[cell] = reason
	return {"counts": counts, "removed": removed}


## 删除半径内墙格（Boss 登场清除），返回被删格 Array[Vector2i]。
static func clear_in_radius(wall_set: Dictionary, world_of: Callable, center: Vector2, radius: float) -> Array:
	var removed: Array = []
	if radius <= 0.0:
		return removed
	for cell in wall_set.keys():
		if not (cell is Vector2i):
			continue
		var world: Vector2 = world_of.call(cell)
		if world.distance_to(center) < radius:
			removed.append(cell)
			wall_set.erase(cell)
	return removed


static func _within_any(world: Vector2, positions: Array, radius: float) -> bool:
	if radius <= 0.0 or positions.is_empty():
		return false
	for pos in positions:
		if pos is Vector2 and world.distance_to(pos) < radius:
			return true
	return false


# ---------------- 格连通图 ----------------

static func bfs_reachable(seed: Vector2i, free: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if not free.has(seed):
		return out
	var queue: Array[Vector2i] = [seed]
	out[seed] = true
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for offset in NEIGHBOR_OFFSETS:
			var next: Vector2i = current + offset
			if free.has(next) and not out.has(next):
				out[next] = true
				queue.append(next)
	return out


static func find_wall_bridge(wall_set: Dictionary, reachable: Dictionary, free: Dictionary) -> Array[Vector2i]:
	var starts: Array[Vector2i] = []
	var goals: Dictionary = {}
	for cell in wall_set.keys():
		if not (cell is Vector2i):
			continue
		var start := false
		var goal := false
		for offset in NEIGHBOR_OFFSETS:
			var next: Vector2i = cell + offset
			if free.has(next) and not reachable.has(next):
				start = true
			if reachable.has(next):
				goal = true
		if start:
			starts.append(cell)
		if goal:
			goals[cell] = true
	if starts.is_empty() or goals.is_empty():
		return []
	var parents: Dictionary = {}
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []
	for start in starts:
		if not visited.has(start):
			visited[start] = true
			queue.append(start)
	var head := 0
	var found := INVALID_CELL
	while head < queue.size():
		var current := queue[head]
		head += 1
		if goals.has(current):
			found = current
			break
		for offset in NEIGHBOR_OFFSETS:
			var next: Vector2i = current + offset
			if wall_set.has(next) and not visited.has(next):
				visited[next] = true
				parents[next] = current
				queue.append(next)
	if found == INVALID_CELL:
		return []
	var path: Array[Vector2i] = []
	var current := found
	while true:
		path.append(current)
		if parents.has(current):
			current = parents[current]
		else:
			break
	path.reverse()
	return path


# ---------------- 随机墙（Optional）连通回收 ----------------

## Core 是作者基线（只读）；只有 Optional（随机墙）会因把原本可走区域隔断而被回收。
## Core 自己不可达的格（被大块实心墙围住）视为不可通行区域，只作 core_unreachable 信息。
##
## 返回:
##   ok: Optional 回收后，Core 基线下原本可走的格是否仍全部可达
##   core_unreachable: Core 自身不可达的可行走格（信息，不处理）
##   optional_removed: 被回收的 Optional 格
##   dropped_all_optional: 是否本轮丢弃全部 Optional
##   wall / kept_optional: 最终结果
##   missing_after: 回收后仍缺失的格（异常，通常应为空）
static func repair_optional_connectivity(core: Dictionary, optional: Dictionary,
		walkable: Dictionary, seed: Vector2i) -> Dictionary:
	var result := {
		"ok": true,
		"core_unreachable": {},
		"optional_removed": [],
		"dropped_all_optional": false,
		"kept_optional": optional.duplicate(true),
		"wall": {},
		"missing_after": {},
	}

	var free_core := _free_of(walkable, core)
	var reachable_core := bfs_reachable(seed, free_core)
	var core_unreachable: Dictionary = {}
	for cell in free_core.keys():
		if not reachable_core.has(cell):
			core_unreachable[cell] = true
	result["core_unreachable"] = core_unreachable

	if not free_core.has(seed) or reachable_core.is_empty():
		# 玩家格本身不可走：无法定义可通行基线；保留现状，由调用方处理。
		result["ok"] = false
		result["wall"] = _union(core, optional)
		return result

	var required: Dictionary = reachable_core
	var kept_optional: Dictionary = optional.duplicate(true)
	var optional_removed: Array = []
	var dropped_all := false
	var guard := maxi(8, optional.size() + 8)
	while guard > 0:
		guard -= 1
		var state := _state_with(core, kept_optional, walkable, seed)
		var free: Dictionary = state["free"]
		var reachable: Dictionary = state["reachable"]
		var missing := _missing_of(required, reachable)
		if missing.is_empty():
			var all_removed := dropped_all or (kept_optional.is_empty() and not optional.is_empty())
			result["ok"] = true
			result["wall"] = state["wall"]
			result["kept_optional"] = kept_optional
			result["optional_removed"] = optional_removed
			result["dropped_all_optional"] = all_removed
			result["missing_after"] = {}
			return result
		# 只拆 Optional：沿 Optional 墙找最短拆桥，把被隔断的可走区域接回来。
		var bridge := find_wall_bridge(kept_optional, reachable, free)
		if not bridge.is_empty():
			for cell in bridge:
				if kept_optional.has(cell):
					kept_optional.erase(cell)
					optional_removed.append(cell)
			continue
		# Optional 单独修不好：本轮随机墙全部不生成，Core 保持。
		if not kept_optional.is_empty():
			for cell in kept_optional.keys():
				optional_removed.append(cell)
			kept_optional.clear()
			dropped_all = true
			continue
		break

	var final_state := _state_with(core, kept_optional, walkable, seed)
	var final_missing := _missing_of(required, final_state["reachable"])
	result["ok"] = final_missing.is_empty()
	result["wall"] = final_state["wall"]
	result["kept_optional"] = kept_optional
	result["optional_removed"] = optional_removed
	result["dropped_all_optional"] = dropped_all or (kept_optional.is_empty() and not optional.is_empty())
	result["missing_after"] = final_missing
	return result


static func _state_with(core: Dictionary, optional: Dictionary, walkable: Dictionary,
		seed: Vector2i) -> Dictionary:
	var wall := _union(core, optional)
	var free := _free_of(walkable, wall)
	return {
		"wall": wall,
		"free": free,
		"reachable": bfs_reachable(seed, free),
	}


static func _free_of(walkable: Dictionary, wall: Dictionary) -> Dictionary:
	var free: Dictionary = {}
	for cell in walkable.keys():
		if not wall.has(cell):
			free[cell] = true
	return free


static func _union(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for cell in a.keys():
		out[cell] = true
	for cell in b.keys():
		out[cell] = true
	return out


static func _missing_of(required: Dictionary, reachable: Dictionary) -> Dictionary:
	var missing: Dictionary = {}
	for cell in required.keys():
		if not reachable.has(cell):
			missing[cell] = true
	return missing
