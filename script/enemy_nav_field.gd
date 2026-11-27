class_name EnemyNavField

## 敌人共享导航场（静态服务，不注册 autoload）。
##
## 数据源：MapChunks 的可行走格集合（与场地词条同一套格子，等距 64x32，
## 四邻接在世界空间的间距恒等，因此用等权 BFS 即可，无需优先队列）。
##
## 每张场 = 以某个玩家所在格为种子的一次 BFS：
##   dist[cell] = 到该玩家的步数（不可达为 INF）
##   flow[cell] = 指向 dist 更小邻居的世界空间单位向量
##
## 阻挡集有两种来源：
##   1. 显式注册（场地词条走 add_block/remove_block，按来源引用计数）
##   2. 建拓扑时自动扫描 StaticBody2D 且 collision_layer 含 wall(256) 的碰撞体 AABB
##      —— 只认静态体，绝不把 Boss/敌人/玩家（CharacterBody2D）误标成障碍。
##
## 约定：任何查询在场未就绪时返回 ZERO/INF/true，调用方据此退回"直冲"（今天的旧行为）。

const REBUILD_MIN_MS := 200
## 仅 complex path 使用；覆盖 4 名玩家 + 最多 4 个全息/残影目标（静态目标可复用场）。
## 4 玩家 + 4 全息正好顶满 8，溢出会淘汰活跃场后反复重建 → 提到 12。
const MAX_FIELDS := 12
## 单帧场重建预算（µs）：多目标同帧串行重建时，超预算的场保留旧值、下一轮补建。
static var rebuild_budget_us: int = 3000
## seed 差 1 格时允许复用的最短时间窗；本地组按完整槽位周期（3×600ms）给足。
const REUSE_WINDOW_MIN_MS := 400
const REUSE_WINDOW_LOCAL_MS := 1800
## 远端玩家组：host 侧输入本身就是插值镜像（精度有限），复用窗口可以放宽。
const REUSE_WINDOW_REMOTE_MS := 2500
const WALL_LAYER := 256
const OBSTACLE_INFLATE := 28.0
const SCAN_MAX_DEPTH := 32
## 运行时障碍 TileMapLayer 组：EnemyNavField 建拓扑时直接扫描其 used cells。
const OBSTACLE_GROUP := &"NavObstacle"
## 玩家/锚点周围允许流场穿越的 goal 区半径（格）；只放宽流场，不放宽可站格。
const GOAL_ZONE_RADIUS_CELLS := 3
## goal 区接不到 body-safe 时，沿同一 free 连通域找最近安全点的最大步数。
const GOAL_FALLBACK_MAX_CELLS := 12
## 玩家 body-safe 连通块小于该值时视为“安全孤岛”，攻击锚点落到岛外最近安全格。
const PLAYER_ISLAND_MAX_CELLS := 6
## 安全岛外攻击点的最大 free 路径搜索步数。
const ATTACK_ANCHOR_SEARCH_CELLS := 10
## target_safe 的局部搜索半径（格）；防止 U 形开口把安全点带到外面。
const TARGET_SAFE_RADIUS := 3
## target 脚下格若 solid，只在附近这个半径内找最近非 solid 格，不跳到远处。
const TARGET_SOLID_SNAP_RADIUS := 3
## 玩家相连 free 口袋的最大格数：只放宽玩家身边，避免整图放行。
const PLAYER_POCKET_MAX_CELLS := 16
## 极简模式：flow 只避开 solid，不做 body-safe/near-solid/goal_zone；目标只指向玩家。
## 默认关闭，使用 clearance/local-wall body-safe；保留开关便于对比。
static var simple_field_mode: bool = false

## 移动策略模式：
##   PURE_FIELD      = 只按场流走（之前的纯场实验）
##   FIELD_STRATEGY  = 场负责绕墙/前进，阵型/密度/队列/墙推只做受约束的横向/安全修正
##   LEGACY          = 旧的 flow + 阵型 + 密度 + 墙推 + 局部避障
enum MoveMode { PURE_FIELD, FIELD_STRATEGY, LEGACY }
static var move_mode := MoveMode.FIELD_STRATEGY

## 只有壁垒词条需要复杂场寻路；其它场景关闭，AI 走直连/阵型决策。
static var complex_path_enabled: bool = false

const NEIGHBORS4 := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

## 8 邻域 flow：直线 1.0，对角 √2，避免 4 邻域在 U 形/斜墙里绕外圈。
## reload: diagonal 变量显式 bool（2026-11-06）
const NEIGHBORS8 := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
## 与 NEIGHBORS8 的四个对角方向同序，值为对应两条正交边的方向下标。
const DIAGONAL_SIDES := [Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 2), Vector2i(1, 3)]
const DIAGONAL_COST := 1.41421356237
## `_rebuild_solid` 的 8 邻域偏移（常量表，避免每格新建数组）。
const NEIGHBOR_OFFSETS9 := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

class Field:
	var seed_cell: Vector2i = Vector2i.ZERO
	## body_ok/local_walls/player_pocket 按这个格缓存；只有它变化才重建身体层。
	var body_seed: Vector2i = Vector2i(2147483647, 2147483647)
	## 实际 BFS 起点；常态等于 seed_cell，深 nook 时会退到同连通域最近安全点。
	var start_cell: Vector2i = Vector2i.ZERO
	## AI 阵型/攻击锚点：敌人实际可站的 body-safe 点；安全孤岛时在岛外。
	var attack_cell: Vector2i = Vector2i.ZERO
	## 流场 goal_zone：seed/玩家周围允许穿越的贴墙格（调试/可视化用）。
	var goal_zone: Dictionary = {}
	## 玩家相连的墙连通块：这些墙的 near-solid 不再把玩家附近推远。
	var local_walls: Dictionary = {}
	## 玩家相连的 free 口袋（限格数）：这些格可靠近玩家，即使贴墙。
	var player_pocket: Dictionary = {}
	## 每格是否可被敌人身体接近：clearance 通过，或属于 player_pocket。
	var body_ok := PackedByteArray()
	## 玩家侧 body-safe 连通域缓存：按玩家安全格缓存一次，供 is_target_reachable_from 复用。
	var player_component: Dictionary = {}
	var player_component_cell: Vector2i = Vector2i(2147483647, 2147483647)
	## 玩家侧最近 body-safe 格（field.dist 最小），safe/attack 直接读它。
	var safe_cell: Vector2i = Vector2i.ZERO
	var safe_valid: bool = false
	var dist := PackedFloat32Array()
	var flow := PackedVector2Array()
	## 单场版本号：只有这张场重建时 +1（替代全局 epoch，避免一张场重建让所有敌人缓存失效）。
	var epoch: int = 0
	var alive: bool = false
	var built_ms: int = 0

static var _built: bool = false
static var _sig: int = 0
static var _cells: Array[Vector2i] = []
static var _index: Dictionary = {}
static var _flow_grid_cells: Array[Vector2i] = []
static var _flow_neighbors := PackedInt32Array()
static var _world := PackedVector2Array()

# 自动探测到的静态障碍格（建拓扑时刷新）
static var _solid_auto: Dictionary = {}
# 显式注册的阻挡：source_id -> Array[Vector2i]，以及每格引用计数
static var _block_sources: Dictionary = {}
static var _block_counts: Dictionary = {}
# 合并后的阻挡集（BFS / is_solid 都读它）
static var _solid: Dictionary = {}
# 每格"离墙余量是否足够站人"（一次性预计算，替代逐次 point_in_polygon）
static var _margin_ok := PackedByteArray()
# 每格格心到可行走边界的余量（px，二分 nearest_inside 求得，误差 <1px）
static var _clearance := PackedFloat32Array()
const SLOT_MARGIN := 24.0
# 每格格心到最近 solid 格几何边缘的距离（px）；body-safe 的主判据
static var _wall_clearance := PackedFloat32Array()
## 每格最近 solid 格；_cell_body_safe_local 用它决定是否需要 excluding 全扫。
static var _wall_nearest: Array[Vector2i] = []
static var _wall_probe_nearest: Vector2i = Vector2i.ZERO
# 身体安全阈值：一格宽通道约 32px，敌人半径约 12，16~18 可同时放行通道/挡住窄缝
const BODY_CLEARANCE := 16.0
# 每格 8 邻域是否含阻挡格（用于墙探针的快速放行）
static var _near_solid := PackedByteArray()
# 格内任意点到格心的最大距离（64×32 格的半对角 35.8，留 1px 余量）
const CELL_SPAN := 37.0

static var _fields: Dictionary = {}
# 场版本号：每次重建/清空 +1。敌人用它判断"场流采样结果还能不能复用"。
static var epoch: int = 0
## 拓扑版本：只在 invalidate/拓扑重建时 +1（与单场重建的 epoch 分离）。
static var topology_epoch: int = 0
## 单帧重建预算消耗（按物理帧重置）：多目标同帧串行重建时削峰。
static var _rebuild_spent_us: int = 0
static var _rebuild_budget_frame: int = -1
static var pending_rebuild: bool = false
## 分帧建场队列按入队顺序保存目标 instance id 和敌人侧起点，随拓扑失效清空。
## 只由真实调度（ensure_rebuilt(..., scheduled=true)）入队；每物理帧最多补建一张。
static var _pending: Dictionary = {}
## 本物理帧是否已实际重建过一张场：保证排队任务不会在同一帧连建。
static var _last_build_frame: int = -1
static var _last_build_process_frame: int = -1
## 观测计数：场重建/复用次数（F3 与 ai_probe 用）。
static var rebuild_count: int = 0
static var reuse_count: int = 0
## 最近一次拓扑重建的分段耗时（µs），供 ai_probe / F3 定位尖峰。
static var topology_profile: Dictionary = {}
## 同世界点 → 同格 的单槽缓存（AI 每帧对同一位置多次查格）。
static var _at_pos: Vector2 = Vector2(INF, INF)
static var _at_index: int = -1
## 最近 body-safe 点缓存：格索引 → 世界点（刷怪/脱困低频路径复用）。
static var _safe_point_cache: Dictionary = {}
## 最近 body-safe 格索引缓存：seed 格 → 格索引。
static var _nearest_safe_cache: Dictionary = {}
## `_solid` 的格坐标分块索引：墙距只扫邻近块的 solid，避免 729×solid 全扫。
const WALL_BUCKET := 4
static var _solid_buckets: Dictionary = {}
## has_blocks 的帧级缓存（壁垒墙只在回合边界/清墙时变化）。
static var _has_blocks_frame: int = -1
static var _has_blocks_value: bool = false


# ---------------- 阻挡注册 ----------------

static func has_blocks() -> bool:
	# 显式注册的场地阻挡，或场景里 NavObstacle 组的 TileMapLayer 有实际格子。
	# 后者让壁垒这类“视觉/碰撞都是 TileMapLayer”的障碍不需要再手动 add_block。
	var frame := Engine.get_physics_frames()
	if frame == _has_blocks_frame:
		return _has_blocks_value
	_has_blocks_frame = frame
	_has_blocks_value = not _block_counts.is_empty() or has_obstacle_tilemaps()
	return _has_blocks_value


static func has_obstacle_tilemaps() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	for node in tree.get_nodes_in_group(OBSTACLE_GROUP):
		if node is TileMapLayer:
			if not (node as TileMapLayer).get_used_cells().is_empty():
				return true
		elif node is TileMap:
			var map := node as TileMap
			for layer_index in map.get_layers_count():
				if not map.get_used_cells(layer_index).is_empty():
					return true
	return false


static func add_block(source_id: String, cells: Array) -> void:
	if source_id == "":
		return
	remove_block(source_id)
	var unique: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cell in cells:
		if cell is Vector2i and not seen.has(cell):
			seen[cell] = true
			unique.append(cell)
	if unique.is_empty():
		return
	_block_sources[source_id] = unique
	for cell in unique:
		_block_counts[cell] = int(_block_counts.get(cell, 0)) + 1
	_on_blocks_changed()


static func remove_block(source_id: String) -> void:
	if not _block_sources.has(source_id):
		return
	for cell in _block_sources[source_id]:
		var n: int = int(_block_counts.get(cell, 0)) - 1
		if n <= 0:
			_block_counts.erase(cell)
		else:
			_block_counts[cell] = n
	_block_sources.erase(source_id)
	_on_blocks_changed()


static func clear_blocks() -> void:
	if _block_sources.is_empty() and _block_counts.is_empty():
		return
	_block_sources.clear()
	_block_counts.clear()
	_on_blocks_changed()


static func _on_blocks_changed() -> void:
	_has_blocks_frame = -1
	_rebuild_solid()
	_clear_fields()


# ---------------- 失效 / 生命周期 ----------------

static func invalidate() -> void:
	_built = false
	_sig = 0
	_cells.clear()
	_index.clear()
	_world = PackedVector2Array()
	_solid.clear()
	_solid_auto.clear()
	_solid_buckets.clear()
	_at_pos = Vector2(INF, INF)
	_at_index = -1
	_safe_point_cache.clear()
	_nearest_safe_cache.clear()
	_has_blocks_frame = -1
	topology_epoch += 1
	_clear_fields()


static func is_ready(target: Node2D = null) -> bool:
	if not complex_path_enabled:
		return false
	if not _built:
		return false
	if _fields.is_empty():
		return false
	if target == null:
		return true
	var field: Field = _fields.get(target.get_instance_id())
	return field != null and field.alive


## 只建拓扑/阻挡表，不建 BFS 场；刷怪逻辑在 AI 还没求解时也能查询障碍。
static func ensure_topology() -> bool:
	return _ensure_topology()


static func _clear_fields() -> void:
	_fields.clear()
	_clear_pending()
	epoch += 1


## 只读：单场版本号（该目标自己的场重建时 +1）。敌人用它判断场流采样是否还能复用。
## 用 -1 表示"该目标当前没有场"，敌人会跳过缓存走完整采样。
static func field_epoch(target: Node2D = null) -> int:
	var field := _field_for(target)
	return field.epoch if field != null else -1


# ---------------- 拓扑 ----------------

static func _map_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("Map")


static func _compute_signature() -> int:
	var map := _map_node()
	if map == null or not is_instance_valid(map):
		return 0
	var poly := MapChunks.get_walkable_polygon()
	if poly.size() < 3:
		return 0
	if MapBounds.get_boundary_source() != &"walls":
		return 0
	var sig: int = map.get_instance_id()
	for point in poly:
		sig = (sig * 31 + int(round(point.x * 10.0))) ^ int(round(point.y * 10.0))
	return sig


static func _ensure_topology() -> bool:
	var sig := _compute_signature()
	if sig == 0:
		return false
	if _built and sig == _sig:
		return true
	_build_topology(sig)
	return _built


static func _build_topology(sig: int) -> void:
	var t_all := Time.get_ticks_usec()
	var t_mark := t_all
	var cells := MapChunks.get_all_cells()
	_built = false
	_sig = sig
	_cells = cells
	_index.clear()
	_world = PackedVector2Array()
	_world.resize(_cells.size())
	_margin_ok.resize(_cells.size())
	_clearance.resize(_cells.size())
	# 拓扑只在 boundary_source=="walls" 时构建，此时 hull 是四向射线命中的 4 点菱形（凸）。
	# 一次取出，供每格的 clearance 解析计算，避免 729 × 8 次 nearest_inside。
	var hull := MapChunks.get_walkable_polygon()
	var t_grid := Time.get_ticks_usec()
	for i in _cells.size():
		_index[_cells[i]] = i
		_world[i] = MapChunks.get_cell_world(_cells[i])
		var margin := MapBounds.nearest_inside(_world[i], SLOT_MARGIN)
		_margin_ok[i] = 1 if margin == _world[i] else 0
		_clearance[i] = _measure_clearance(_world[i], hull)
	_prepare_flow_neighbors()
	var t_scan := Time.get_ticks_usec()
	_scan_static_obstacles()
	var t_solid := Time.get_ticks_usec()
	_rebuild_solid()
	var t_wall := Time.get_ticks_usec()
	_rebuild_wall_clearance()
	var t_end := Time.get_ticks_usec()
	_clear_fields()
	_built = not _cells.is_empty()
	topology_profile = {
		"cells": t_mark - t_all,
		"grid": t_grid - t_mark,
		"scan": t_scan - t_grid,
		"solid": t_solid - t_scan,
		"wall": t_wall - t_solid,
		"clear": t_end - t_wall,
		"total": t_end - t_all,
		"count": _cells.size(),
	}


## 邻格编号只取决于有序地图格。建墙/撤墙只改变通行性，同一格表可复用。
static func _prepare_flow_neighbors() -> void:
	if _flow_grid_cells == _cells:
		return
	_flow_grid_cells = _cells.duplicate()
	_flow_neighbors.resize(_cells.size() * NEIGHBORS8.size())
	for i in _cells.size():
		var base := i * NEIGHBORS8.size()
		for direction in NEIGHBORS8.size():
			_flow_neighbors[base + direction] = int(_index.get(_cells[i] + NEIGHBORS8[direction], -1))


static func _rebuild_solid() -> void:
	_solid.clear()
	for cell in _solid_auto:
		_solid[cell] = true
	for cell in _block_counts:
		_solid[cell] = true
	# 8 邻域阻挡表（墙探针的快速放行用；必须随 _solid 一起刷新）。
	# 从 solid 格反向标记邻格：复杂度 = solid 格数 × 9，而不是 729 格 × 8 次 dict 查。
	_near_solid.resize(_cells.size())
	_near_solid.fill(0)
	for cell in _solid:
		var index := int(_index.get(cell, -1))
		if index >= 0:
			_near_solid[index] = 1
		for offset in NEIGHBOR_OFFSETS9:
			var ni := int(_index.get(cell + offset, -1))
			if ni >= 0:
				_near_solid[ni] = 1
	_rebuild_solid_buckets()


## `_solid` 按格坐标分块（WALL_BUCKET 格一块），供墙距/最近格查询只扫邻近块。
static func _rebuild_solid_buckets() -> void:
	_solid_buckets.clear()
	for cell in _solid:
		var key := Vector2i(floori(float(cell.x) / WALL_BUCKET), floori(float(cell.y) / WALL_BUCKET))
		var list = _solid_buckets.get(key)
		if list == null:
			list = []
			_solid_buckets[key] = list
		list.append(cell)


## 邻近（±radius_buckets 个块）的 solid 格列表；没有索引时回退全量。
static func _nearby_solid_cells(cell: Vector2i, radius_buckets: int = 1) -> Array:
	if _solid_buckets.is_empty():
		return _solid.keys()
	var out: Array = []
	var cx := floori(float(cell.x) / WALL_BUCKET)
	var cy := floori(float(cell.y) / WALL_BUCKET)
	for bx in range(cx - radius_buckets, cx + radius_buckets + 1):
		for by in range(cy - radius_buckets, cy + radius_buckets + 1):
			var list = _solid_buckets.get(Vector2i(bx, by))
			if list == null:
				continue
			out.append_array(list)
	return out


## 一次拓扑重建内，同一分块的格子共享候选墙列表及世界坐标。
static func _rebuild_wall_clearance() -> void:
	_wall_clearance.resize(_cells.size())
	_wall_nearest.resize(_cells.size())
	if _solid.is_empty():
		_wall_clearance.fill(1000.0)
		_wall_nearest.fill(_wall_probe_nearest)
		return
	var nearby_by_bucket := {}
	var worlds_by_bucket := {}
	for i in _cells.size():
		var cell: Vector2i = _cells[i]
		var bucket := Vector2i(floori(float(cell.x) / WALL_BUCKET), floori(float(cell.y) / WALL_BUCKET))
		if not nearby_by_bucket.has(bucket):
			var nearby := _nearby_solid_cells(cell)
			nearby_by_bucket[bucket] = nearby
			worlds_by_bucket[bucket] = _wall_centers(nearby)
		_wall_clearance[i] = _nearest_wall_distance(_world[i], nearby_by_bucket[bucket], worlds_by_bucket[bucket])
		_wall_nearest[i] = _wall_probe_nearest


static func _wall_centers(candidates: Array) -> PackedVector2Array:
	var centers := PackedVector2Array()
	centers.resize(candidates.size())
	for i in candidates.size():
		var index := int(_index.get(candidates[i], -1))
		centers[i] = _world[index] if index >= 0 else MapChunks.get_cell_world(candidates[i])
	return centers


static func _measure_wall_clearance(center: Vector2, center_cell: Vector2i = Vector2i(2147483647, 2147483647)) -> float:
	if _solid.is_empty():
		return 1000.0
	var candidates := _nearby_solid_cells(center_cell) if center_cell != Vector2i(2147483647, 2147483647) else _solid.keys()
	return _nearest_wall_distance(center, candidates, _wall_centers(candidates))


static func _nearest_wall_distance(center: Vector2, candidates: Array, centers: PackedVector2Array) -> float:
	# 每个墙格的锚点本身就是菱形的底角。离查询点最近的底角给出可靠的距离上界。
	var vertex_limit_sq := 1000.0 * 1000.0
	for corner in centers:
		vertex_limit_sq = minf(vertex_limit_sq, center.distance_squared_to(corner))
	var limit := sqrt(vertex_limit_sq)
	var best := 1000.0
	_wall_probe_nearest = Vector2i.ZERO
	for i in centers.size():
		var bottom := centers[i]
		var left := bottom + Vector2(-32, -16)
		var top := bottom + Vector2(0, -32)
		var right := bottom + Vector2(32, -16)
		# 用实际世界坐标顶点界定包围盒，并为浮点舍入留 1px。候选仍按原顺序比较。
		var margin := limit + 1.0
		if center.x < left.x - margin or center.x > right.x + margin:
			continue
		if center.y < top.y - margin or center.y > bottom.y + margin:
			continue
		var d := minf(_point_segment_distance(center, bottom, left), _point_segment_distance(center, left, top))
		d = minf(d, _point_segment_distance(center, top, right))
		d = minf(d, _point_segment_distance(center, right, bottom))
		if d < best:
			best = d
			limit = minf(limit, best)
			_wall_probe_nearest = candidates[i]
	return best


static func _point_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# ---------------- 自动障碍扫描 ----------------

static func _scan_static_obstacles() -> void:
	_solid_auto.clear()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var root := tree.current_scene
	if root != null:
		_scan_node(root, 0)
	# 运行时障碍 TileMapLayer：只扫描 NavObstacle 组，避免把主地图 Wall/SpawnMap 当成障碍。
	for node in tree.get_nodes_in_group(OBSTACLE_GROUP):
		_mark_obstacle_tilemap(node)


static func _mark_obstacle_tilemap(node: Node) -> void:
	if node is TileMapLayer:
		var layer := node as TileMapLayer
		for cell in layer.get_used_cells():
			_mark_obstacle_cell(layer, cell)
	elif node is TileMap:
		var map := node as TileMap
		for layer_index in map.get_layers_count():
			for cell in map.get_used_cells(layer_index):
				_mark_obstacle_cell(map, cell)


static func _mark_obstacle_cell(node: Node2D, cell: Vector2i) -> void:
	var world: Vector2 = node.to_global(node.map_to_local(cell))
	var map_cell := MapChunks.world_to_cell(world)
	if _index.has(map_cell):
		_solid_auto[map_cell] = true


static func _scan_node(node: Node, depth: int) -> void:
	if node is StaticBody2D:
		var body := node as StaticBody2D
		if (body.collision_layer & WALL_LAYER) != 0:
			_mark_static_body(body)
	if depth >= SCAN_MAX_DEPTH:
		return
	# 墙/StaticBody2D 只可能挂在世界层（Node2D）下：跳过 UI（Control）与 CanvasLayer 子树，
	# 否则每次拓扑重建都要遍历全部 UI/菜单节点（实测 scan 占拓扑 4.3ms）。
	if node is Control or node is CanvasLayer:
		return
	# 用 get_child_count/get_child 而不是 get_children()：后者每个节点都分配一个数组。
	for i in node.get_child_count():
		_scan_node(node.get_child(i), depth + 1)


static func _mark_static_body(body: StaticBody2D) -> void:
	var marked := false
	for child in body.get_children():
		if not (child is CollisionShape2D):
			continue
		var shape_node := child as CollisionShape2D
		var shape := shape_node.shape
		if shape == null:
			continue
		var rect := _shape_world_rect(shape, shape_node.global_transform)
		if rect.size == Vector2.ZERO:
			continue
		_mark_rect(rect)
		marked = true
	if marked:
		return
	# 无碰撞形状（或形状无效）时退化为以本体位置为中心的小块
	_mark_rect(Rect2(body.global_position - Vector2(16, 16), Vector2(32, 32)))


static func _shape_world_rect(shape: Shape2D, xf: Transform2D) -> Rect2:
	var local := shape.get_rect()
	var p0 := xf * local.position
	var p1 := xf * (local.position + Vector2(local.size.x, 0.0))
	var p2 := xf * (local.position + Vector2(0.0, local.size.y))
	var p3 := xf * (local.position + local.size)
	var rect := Rect2(p0, Vector2.ZERO)
	rect = rect.expand(p1)
	rect = rect.expand(p2)
	rect = rect.expand(p3)
	return rect


static func _mark_rect(rect: Rect2) -> void:
	var grown := rect.grow(OBSTACLE_INFLATE)
	# 等距格与 AABB 不对齐：按两角求格范围后外扩 2 格，再逐格精确判点（不外扩会漏标边缘格）。
	var c0 := MapChunks.world_to_cell(grown.position)
	var c1 := MapChunks.world_to_cell(grown.end)
	if c0 == MapChunks.INVALID_CELL or c1 == MapChunks.INVALID_CELL:
		return
	var x0 := mini(c0.x, c1.x) - 2
	var x1 := maxi(c0.x, c1.x) + 2
	var y0 := mini(c0.y, c1.y) - 2
	var y1 := maxi(c0.y, c1.y) + 2
	if (x1 - x0 + 1) * (y1 - y0 + 1) > _cells.size():
		# 范围比全图还大（常见于大静物）：仍全扫，避免范围外扩后遍历更多空格。
		for i in _cells.size():
			if grown.has_point(_world[i]):
				_solid_auto[_cells[i]] = true
		return
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var cell := Vector2i(x, y)
			var index := int(_index.get(cell, -1))
			if index < 0:
				continue
			if grown.has_point(_world[index]):
				_solid_auto[cell] = true


# ---------------- 场构建 ----------------

## `scheduled=true` 是真实运行路径（EnemyAI 组求解）：多张冷目标场分帧构建，
## 每物理帧最多建一张，本地玩家优先；单目标/调试直接调用保持原来的同步语义。
static func ensure_rebuilt(target: Node2D, anchor: Vector2 = Vector2.ZERO, from_pos: Vector2 = Vector2.ZERO, scheduled: bool = false) -> bool:
	if not complex_path_enabled:
		return false
	if target == null or not is_instance_valid(target):
		return false
	if not _ensure_topology():
		return false
	var now := Time.get_ticks_msec()
	var key := target.get_instance_id()
	var base_point: Vector2 = anchor if anchor != Vector2.ZERO else target_anchor(target)
	var seed: Vector2i = MapChunks.world_to_cell(base_point)
	# 预判点若落在障碍格里，退回目标自身的撞墙碰撞中心（不是脚下/精灵中心）。
	if _solid.has(seed):
		seed = MapChunks.world_to_cell(target_anchor(target))
	# goal 与 standable 分离：玩家/锚点贴墙（仅 _near_solid）时保留原格作为 goal；
	# 只有 solid/越界才改取最近 body-safe 格，避免贴墙玩家被换到远处导致敌人不靠近。
	var seed_index := int(_index.get(seed, -1))
	if seed_index < 0 or _solid.has(seed):
		var safe_index := _nearest_body_safe_index(seed)
		if safe_index >= 0:
			seed = _cells[safe_index]
	if simple_field_mode:
		var simple_field: Field = _fields.get(key)
		if _field_reusable(simple_field, seed, now, target):
			_drop_pending(key)
			return true
		if simple_field == null:
			_prune_fields()
			if _fields.size() >= MAX_FIELDS:
				_evict_one()
			simple_field = Field.new()
			_fields[key] = simple_field
		_rebuild_field(simple_field, seed, -1)
		_mark_field_built(key)
		return simple_field.alive
	var field: Field = _fields.get(key)
	# 复用命中：只用 O(1) 的玩家侧 safe 格刷新攻击点，跳过 _choose_attack_index 的整图 BFS。
	# （旧实现无条件先算 _choose_attack_index，随后结果又被 target_safe 覆盖，属纯浪费。）
	if field != null and field.alive and _field_reusable(field, seed, now, target):
		reuse_count += 1
		_drop_pending(key)
		_refresh_attack_from_safe(field, target)
		return true
	# 真实调度：本帧已建过一张场（或预算用尽）就排队，下一物理帧补建。
	# 冷场（field == null）以前绕过预算，四目标建墙后 3 张场同帧首建是 30ms 尖峰的主因。
	if scheduled and (field == null or not field.alive):
		if _pending.has(key) or not _can_start_cold_field():
			_queue_pending(key, from_pos)
			return false
	if field != null and field.alive and _rebuild_budget_left() <= 0:
		pending_rebuild = true
		_refresh_attack_from_safe(field, target)
		return true
	if field == null:
		_prune_fields()
		if _fields.size() >= MAX_FIELDS:
			_evict_one()
		field = Field.new()
		_fields[key] = field
	# 只有玩家侧 safe 格不可用时才需要 _choose_attack_index（2 次整图 BFS + 全扫）；
	# safe 有效时重建末尾的 _refresh_attack_from_safe 会覆盖它（旧实现无条件先算）。
	var attack := -1
	if not _safe_cell_valid(target):
		attack = _choose_attack_index(seed, from_pos)
	# 身体层（local_walls/player_pocket/body_ok）只在玩家 seed 格变化时重建；
	# flow 仍按当前 seed/attack 重算（Dijkstra 便宜），避免 from_pos/攻击点变化触发整层重建。
	var body_same := field.body_seed == seed
	var t0 := Time.get_ticks_usec()
	_rebuild_field(field, seed, attack, not body_same)
	_rebuild_spent_us += Time.get_ticks_usec() - t0
	rebuild_count += 1
	_mark_field_built(key)
	if field.alive:
		# safe/attack 跟 field.dist 走：取流场内最近 body-safe，避免几何最近绕到墙外。
		_refresh_attack_from_safe(field, target)
	return field.alive


## 真实调度（多目标）预排队：只入队，不在这里建场；物理帧泵按本地玩家优先补建。
static func queue_cold_field(target: Node2D, from_pos: Vector2) -> void:
	if target == null or not is_instance_valid(target):
		return
	if complex_path_enabled and _ensure_topology():
		_queue_pending(target.get_instance_id(), from_pos)


static func _can_start_cold_field() -> bool:
	return _last_build_frame != Engine.get_physics_frames() \
			and _last_build_process_frame != Engine.get_process_frames() and _rebuild_budget_left() > 0


static func pump_pending() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if not complex_path_enabled:
		_clear_pending()
		return
	if tree == null or tree.paused:
		return
	var next_id := 0
	for id: int in _pending.keys():
		var target = instance_from_id(id)
		if not _pending_target_valid(target):
			_pending.erase(id)
			continue
		if next_id == 0 or (target.is_in_group("Player") and not instance_from_id(next_id).is_in_group("Player")):
			next_id = id
	if next_id == 0:
		_clear_pending()
		return
	if not _can_start_cold_field():
		return
	var node := instance_from_id(next_id) as Node2D
	var from_pos: Vector2 = _pending[next_id]
	_drop_pending(next_id)
	ensure_rebuilt(node, target_anchor(node), from_pos)


static func _queue_pending(key: int, from_pos: Vector2) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_pending[key] = from_pos
	pending_rebuild = true
	if not tree.physics_frame.is_connected(pump_pending):
		tree.physics_frame.connect(pump_pending)


static func _drop_pending(key: int) -> void:
	if _pending.erase(key) and _pending.is_empty():
		_clear_pending()


static func _clear_pending() -> void:
	_pending.clear()
	pending_rebuild = false
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.physics_frame.is_connected(pump_pending):
		tree.physics_frame.disconnect(pump_pending)


static func _mark_field_built(key: int) -> void:
	_last_build_frame = Engine.get_physics_frames()
	_last_build_process_frame = Engine.get_process_frames()
	_drop_pending(key)
	pending_rebuild = not _pending.is_empty()


## 目标失效/倒地/死亡/离场/不再是导航目标：排队任务直接丢弃，不建场。
static func _pending_target_valid(target) -> bool:
	if target == null or not (target is Node2D) or not is_instance_valid(target):
		return false
	var node := target as Node
	if node.is_queued_for_deletion() or not node.is_inside_tree():
		return false
	if node.get("is_downed") == true:
		return false
	var stats = node.get("stats")
	if stats != null and stats is Object:
		var hp = stats.get("hp")
		if hp != null and int(hp) <= 0:
			return false
	if node.has_method("is_threat_nav_target") and not node.is_threat_nav_target():
		return false
	return true


static func _field_reusable(field: Field, seed: Vector2i, now: int, target: Node2D = null) -> bool:
	if field == null or not field.alive:
		return false
	if field.seed_cell == seed:
		# 命中复用必须刷新 built_ms，否则该场会被 _evict_one 当成"最旧"优先淘汰后立刻重建。
		field.built_ms = now
		return true
	var dx: int = abs(field.seed_cell.x - seed.x)
	var dy: int = abs(field.seed_cell.y - seed.y)
	if dx > 1 or dy > 1:
		return false
	var window := REUSE_WINDOW_LOCAL_MS
	if target != null and target.is_in_group("RemotePlayer"):
		# host 侧远端镜像本身就是插值结果，精度有限，复用窗口可放宽、少重建。
		window = REUSE_WINDOW_REMOTE_MS
	if now - field.built_ms < window:
		field.built_ms = now
		return true
	return false


## 单帧重建预算：按物理帧重置，避免多目标在同一帧串行重建导致掉帧。
static func _rebuild_budget_left() -> int:
	var frame := Engine.get_physics_frames()
	if frame != _rebuild_budget_frame:
		_rebuild_budget_frame = frame
		_rebuild_spent_us = 0
	return rebuild_budget_us - _rebuild_spent_us


## 用 O(1) 的玩家侧安全格刷新攻击点；safe 无效时保留旧值（完整版本只有重建时才需要）。
static func _refresh_attack_from_safe(field: Field, target: Node2D) -> void:
	if field == null:
		return
	var safe_cell := target_safe_cell(target)
	if _index.has(safe_cell) and not _solid.has(safe_cell):
		field.attack_cell = safe_cell


## 玩家侧是否存在可用的 safe 格：存在时 attack 直接用它，跳过 _choose_attack_index 的整图 BFS。
static func _safe_cell_valid(target: Node2D) -> bool:
	var safe_cell := target_safe_cell(target)
	return _index.has(safe_cell) and not _solid.has(safe_cell)


## 清理 target 已失效/已死的场，避免它们占着 MAX_FIELDS 名额。
static func _prune_fields() -> void:
	if _fields.is_empty():
		return
	for key in _fields.keys():
		var field: Field = _fields[key]
		if field == null or not field.alive or not is_instance_id_valid(int(key)):
			_fields.erase(key)


static func _evict_one() -> void:
	# 优先淘汰 target 已失效的场；没有才按 built_ms 最旧淘汰。
	for key in _fields:
		if not is_instance_id_valid(int(key)):
			_fields.erase(key)
			return
	var oldest_key: int = 0
	var oldest_ms: int = 2147483647
	var first := true
	for key in _fields:
		var field: Field = _fields[key]
		var ms: int = field.built_ms if field != null else 0
		if first or ms < oldest_ms:
			oldest_ms = ms
			oldest_key = key
			first = false
	_fields.erase(oldest_key)


static func _nearest_body_safe_index(seed: Vector2i) -> int:
	if _cells.is_empty():
		return -1
	var cached := int(_nearest_safe_cache.get(seed, -2))
	if cached != -2:
		return cached
	var anchor := MapChunks.get_cell_world(seed)
	var best := -1
	var best_sq := INF
	for i in _cells.size():
		if not is_cell_body_safe(_cells[i], 1):
			continue
		var d := _world[i].distance_squared_to(anchor)
		if d < best_sq:
			best_sq = d
			best = i
	if _nearest_safe_cache.size() >= 128:
		_nearest_safe_cache.clear()
	_nearest_safe_cache[seed] = best
	return best


# 流场可走 = 格本身非阻挡，且格心到墙面余量 >= BODY_CLEARANCE（1 格宽通道可过）。
static func _cell_flow_blocked(index: int) -> bool:
	if index < 0 or index >= _cells.size():
		return true
	if _solid.has(_cells[index]):
		return true
	if index < _wall_clearance.size():
		return _wall_clearance[index] < BODY_CLEARANCE
	return index < _near_solid.size() and _near_solid[index] == 1


## 预计算 body_ok：clearance/local_walls 通过，或属于玩家 free 口袋。
## 注意：player_pocket 由调用方先算好（见 _rebuild_body_layer），这里不再重复 BFS。
static func _build_body_ok(field: Field, _seed: Vector2i) -> void:
	field.body_ok.resize(_cells.size())
	for i in _cells.size():
		var cell: Vector2i = _cells[i]
		var ok := _cell_body_safe_local(cell, field.local_walls) or field.player_pocket.has(cell)
		field.body_ok[i] = 1 if ok else 0


## body 层增量更新：只有 local_walls / player_pocket 涉及的格需要重算。
## 旧实现每次 seed 变化都重算 729 格（贴墙时还会全扫 solid），是重建尖峰的主项。
static func _rebuild_body_layer(field: Field, seed: Vector2i) -> void:
	var new_walls := _local_wall_component(seed)
	var new_pocket := _player_pocket_cells(seed)
	var same_walls := _same_cell_set(field.local_walls, new_walls)
	var old_pocket: Dictionary = field.player_pocket
	field.local_walls = new_walls
	field.player_pocket = new_pocket
	if not same_walls or field.body_ok.size() != _cells.size():
		_build_body_ok(field, seed)
		return
	# 墙集未变、只有口袋变了：只重算「旧口袋 ∪ 新口袋」这些格。
	var dirty: Dictionary = {}
	for cell in old_pocket:
		dirty[cell] = true
	for cell in new_pocket:
		dirty[cell] = true
	for cell in dirty:
		var index := int(_index.get(cell, -1))
		if index < 0:
			continue
		var ok := _cell_body_safe_local(cell, field.local_walls) or new_pocket.has(cell)
		field.body_ok[index] = 1 if ok else 0


static func _same_cell_set(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for cell in a:
		if not b.has(cell):
			return false
	return true


## 从 body_ok 里取 field.dist 最小的格作为 safe/attack。
static func _update_safe_cell(field: Field) -> void:
	var best := -1
	var best_dist := INF
	for i in _cells.size():
		if i >= field.body_ok.size() or field.body_ok[i] == 0:
			continue
		var d := field.dist[i]
		if d < best_dist:
			best_dist = d
			best = i
	if best >= 0:
		field.safe_cell = _cells[best]
		field.safe_valid = true
	else:
		field.safe_valid = false


static func _rebuild_field(field: Field, seed: Vector2i, attack: int = -1, rebuild_body: bool = true) -> void:
	var n := _cells.size()
	if n <= 0:
		field.alive = false
		return
	field.seed_cell = seed
	if rebuild_body:
		_rebuild_body_layer(field, seed)
		field.body_seed = seed
	if simple_field_mode:
		# 极简：只避开 solid；start=玩家脚下（solid 时取最近非 solid），attack=start。
		var simple_start: int = int(_index.get(seed, -1))
		if simple_start < 0:
			simple_start = _nearest_index(seed)
		if simple_start >= 0 and _solid.has(_cells[simple_start]):
			var free_index := _nearest_free_cell_local(MapChunks.get_cell_world(seed), TARGET_SOLID_SNAP_RADIUS)
			if free_index >= 0:
				simple_start = free_index
		if simple_start < 0:
			field.alive = false
			return
		field.start_cell = _cells[simple_start]
		field.attack_cell = _cells[simple_start]
		field.goal_zone = {}
		_rebuild_flow(field, simple_start, {})
		field.alive = simple_start >= 0
		field.built_ms = Time.get_ticks_msec()
		field.epoch += 1
		epoch += 1
		return
	var goal_zone := _build_goal_zone(seed)
	if attack < 0:
		attack = _choose_attack_index(seed, Vector2.ZERO)
	var start: int = int(_index.get(seed, -1))
	if start < 0:
		start = _nearest_index(seed)
	if start >= 0 and _solid.has(_cells[start]):
		var safe_start := _nearest_body_safe_index(seed)
		if safe_start >= 0:
			start = safe_start
	if start < 0:
		field.alive = false
		return
	field.start_cell = _cells[start]
	field.attack_cell = _cells[attack] if attack >= 0 else _cells[start]
	field.goal_zone = goal_zone
	var body_count := _rebuild_flow(field, start, goal_zone)
	if body_count == 0:
		# goal_zone 接不到任何 body-safe：沿同一 free 连通域找最近安全点，不跨墙。
		var fallback := _nearest_body_safe_in_free_component(seed, GOAL_FALLBACK_MAX_CELLS)
		if fallback >= 0 and fallback != start:
			start = fallback
			field.start_cell = _cells[start]
			if attack < 0:
				field.attack_cell = _cells[start]
			body_count = _rebuild_flow(field, start, goal_zone)
	field.alive = start >= 0
	field.built_ms = Time.get_ticks_msec()
	field.epoch += 1
	epoch += 1


static func _choose_attack_index(seed: Vector2i, from_pos: Vector2 = Vector2.ZERO) -> int:
	if not _index.has(seed):
		return -1
	var seed_index := int(_index.get(seed, -1))
	# 1) 先算玩家侧最近安全点：墙边/小 nook 的 attack 必须贴近玩家。
	var player_side := -1
	if is_cell_body_safe(seed, 1):
		var island := _body_safe_component(seed)
		if island.size() <= PLAYER_ISLAND_MAX_CELLS:
			var outside := _nearest_body_safe_outside_component(seed, island, ATTACK_ANCHOR_SEARCH_CELLS)
			if outside >= 0:
				player_side = outside
		if player_side < 0:
			player_side = seed_index
	else:
		player_side = _nearest_body_safe_in_free_component(seed, GOAL_FALLBACK_MAX_CELLS)
	# 2) 敌人连通域只用于“玩家侧点是否可达”的判断。
	var from_component: Dictionary = {}
	if from_pos != Vector2.ZERO:
		var from_cell := MapChunks.world_to_cell(from_pos)
		var from_index := int(_index.get(from_cell, -1))
		if from_index < 0 or not is_cell_body_safe(from_cell, 1):
			from_index = _nearest_body_safe_index(from_pos)
		if from_index >= 0:
			from_component = _body_safe_component(_cells[from_index])
			if from_component.has(seed):
				return seed_index
	# 3) 玩家侧点可达（或没有敌人位置）时优先它。
	if player_side >= 0:
		if from_component.is_empty() or from_component.has(_cells[player_side]):
			return player_side
	# 4) 玩家侧不可达/跨墙：才回退敌人侧最近点。
	if not from_component.is_empty():
		var nearest := _nearest_cell_in_component(seed, from_component)
		if nearest >= 0:
			return nearest
	return player_side if player_side >= 0 else seed_index


static func _nearest_cell_in_component(seed: Vector2i, component: Dictionary) -> int:
	var anchor := MapChunks.get_cell_world(seed)
	var best := -1
	var best_dist := INF
	for cell in component:
		var index := int(_index.get(cell, -1))
		if index < 0:
			continue
		var d := anchor.distance_squared_to(_world[index])
		if d < best_dist:
			best_dist = d
			best = index
	return best


static func _body_safe_component(seed: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	if not _index.has(seed) or not is_cell_body_safe(seed, 1):
		return out
	var queue: Array[Vector2i] = [seed]
	out[seed] = true
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for offset in NEIGHBORS4:
			var next: Vector2i = cur + offset
			if out.has(next) or not _index.has(next):
				continue
			if not is_cell_body_safe(next, 1):
				continue
			out[next] = true
			queue.append(next)
	return out


static func _nearest_body_safe_outside_component(seed: Vector2i, excluded: Dictionary, max_cells: int) -> int:
	if not _index.has(seed) or _solid.has(seed):
		return -1
	var queue: Array[Vector2i] = [seed]
	var depth: Dictionary = {seed: 0}
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: int = int(depth[cur])
		var index := int(_index.get(cur, -1))
		if index >= 0 and not excluded.has(cur) and is_cell_body_safe(cur, 1):
			return index
		if d >= max_cells:
			continue
		for offset in NEIGHBORS4:
			var next: Vector2i = cur + offset
			if not _index.has(next) or _solid.has(next) or depth.has(next):
				continue
			depth[next] = d + 1
			queue.append(next)
	return -1


static func _build_goal_zone(seed: Vector2i) -> Dictionary:
	var out: Dictionary = {}
	if not _index.has(seed) or _solid.has(seed):
		return out
	var queue: Array[Vector2i] = [seed]
	var depth: Dictionary = {seed: 0}
	out[seed] = true
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: int = int(depth[cur])
		if d >= GOAL_ZONE_RADIUS_CELLS:
			continue
		for offset in NEIGHBORS4:
			var next: Vector2i = cur + offset
			if not _index.has(next) or _solid.has(next) or depth.has(next):
				continue
			depth[next] = d + 1
			out[next] = true
			queue.append(next)
	return out


static func _nearest_body_safe_in_free_component(seed: Vector2i, max_cells: int) -> int:
	if not _index.has(seed) or _solid.has(seed):
		return -1
	var queue: Array[Vector2i] = [seed]
	var depth: Dictionary = {seed: 0}
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: int = int(depth[cur])
		var index := int(_index.get(cur, -1))
		if index >= 0 and is_cell_body_safe(cur, 1):
			return index
		if d >= max_cells:
			continue
		for offset in NEIGHBORS4:
			var next: Vector2i = cur + offset
			if not _index.has(next) or _solid.has(next) or depth.has(next):
				continue
			depth[next] = d + 1
			queue.append(next)
	return -1


static func _flow_passable(index: int, goal_zone: Dictionary, local_walls: Dictionary = {}, field: Field = null) -> bool:
	if index < 0 or index >= _cells.size():
		return false
	var cell: Vector2i = _cells[index]
	if _solid.has(cell):
		return false
	if simple_field_mode:
		return true
	if field != null and index < field.body_ok.size():
		return field.body_ok[index] == 1 or goal_zone.has(cell)
	if not local_walls.is_empty():
		return _cell_body_safe_local(cell, local_walls) or goal_zone.has(cell)
	return not _cell_flow_blocked(index) or goal_zone.has(cell)


## 对角步要求两侧正交格都可通行，避免从两个墙块的夹角斜穿。
static func _diagonal_ok(from_cell: Vector2i, offset: Vector2i, goal_zone: Dictionary,
		local_walls: Dictionary, field: Field = null) -> bool:
	if offset.x == 0 or offset.y == 0:
		return true
	var side_a := int(_index.get(from_cell + Vector2i(offset.x, 0), -1))
	var side_b := int(_index.get(from_cell + Vector2i(0, offset.y), -1))
	return _flow_passable(side_a, goal_zone, local_walls, field) \
		and _flow_passable(side_b, goal_zone, local_walls, field)


static func _rebuild_flow(field: Field, start: int, goal_zone: Dictionary) -> int:
	var n := _cells.size()
	field.dist.resize(n)
	field.flow.resize(n)
	for i in n:
		field.dist[i] = INF
		field.flow[i] = Vector2.ZERO
	# passable 表：重建期内 goal_zone/local_walls/body_ok 都不变，
	# 先算一次，让 Dijkstra/flow 只读表（原来每个邻居要重跑 _flow_passable 3 次，是建场 25ms 的主项）。
	var passable := PackedByteArray()
	passable.resize(n)
	for i in n:
		passable[i] = 1 if _flow_passable(i, goal_zone, field.local_walls, field) else 0
	field.dist[start] = 0.0
	var body_count := 0
	if not _cell_flow_blocked(start):
		body_count += 1
	var heap: Array = []
	_heap_push(heap, 0.0, start)
	while not heap.is_empty():
		var top: Array = _heap_pop(heap)
		var cur_dist := float(top[0])
		var cur := int(top[1])
		if cur_dist > field.dist[cur] + 0.0001:
			continue
		var base := cur * NEIGHBORS8.size()
		for direction in NEIGHBORS8.size():
			var next_index := _flow_neighbors[base + direction]
			if next_index < 0 or passable[next_index] == 0:
				continue
			var diagonal := direction >= 4
			if not simple_field_mode and diagonal:
				# 对角步要求两侧正交格都可通行（等价于 _diagonal_ok，但只读 passable 表）。
				var sides: Vector2i = DIAGONAL_SIDES[direction - 4]
				var side_a := _flow_neighbors[base + sides.x]
				var side_b := _flow_neighbors[base + sides.y]
				if side_a < 0 or side_b < 0 or passable[side_a] == 0 or passable[side_b] == 0:
					continue
			var step := DIAGONAL_COST if diagonal else 1.0
			var next_dist := cur_dist + step
			if next_dist < field.dist[next_index] - 0.0001:
				field.dist[next_index] = next_dist
				if not _cell_flow_blocked(next_index):
					body_count += 1
				_heap_push(heap, next_dist, next_index)
	var safe_best := -1
	var safe_best_dist := INF
	for i in n:
		if passable[i] == 0:
			continue
		# 顺带记录 body_ok 中 dist 最小的格：替代原来单独全扫 729 的 _update_safe_cell。
		if i < field.body_ok.size() and field.body_ok[i] == 1:
			var d_safe: float = field.dist[i]
			if d_safe < safe_best_dist:
				safe_best_dist = d_safe
				safe_best = i
		var base := i * NEIGHBORS8.size()
		var best := -1
		var best_dist: float = field.dist[i]
		for direction in NEIGHBORS8.size():
			var next_index := _flow_neighbors[base + direction]
			if next_index < 0:
				continue
			# start 是玩家/锚点 goal：即使贴墙也允许作为流向终点。
			if next_index != start and passable[next_index] == 0:
				continue
			if not simple_field_mode and direction >= 4:
				var sides: Vector2i = DIAGONAL_SIDES[direction - 4]
				var side_a := _flow_neighbors[base + sides.x]
				var side_b := _flow_neighbors[base + sides.y]
				if side_a < 0 or side_b < 0 or passable[side_a] == 0 or passable[side_b] == 0:
					continue
			if field.dist[next_index] < best_dist:
				best_dist = field.dist[next_index]
				best = next_index
		if best < 0:
			continue
		var direction: Vector2 = _world[best] - _world[i]
		if direction.length_squared() > 0.0001:
			field.flow[i] = direction.normalized()
	if safe_best >= 0:
		field.safe_cell = _cells[safe_best]
		field.safe_valid = true
	else:
		field.safe_valid = false
	return body_count


static func _heap_push(heap: Array, dist: float, index: int) -> void:
	heap.append([dist, index])
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if float(heap[parent][0]) <= float(heap[i][0]):
			break
		var tmp: Array = heap[parent]
		heap[parent] = heap[i]
		heap[i] = tmp
		i = parent


static func _heap_pop(heap: Array) -> Array:
	var root: Array = heap[0]
	var last: Array = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		var count := heap.size()
		while true:
			var left := i * 2 + 1
			var right := left + 1
			var smallest := i
			if left < count and float(heap[left][0]) < float(heap[smallest][0]):
				smallest = left
			if right < count and float(heap[right][0]) < float(heap[smallest][0]):
				smallest = right
			if smallest == i:
				break
			var tmp: Array = heap[smallest]
			heap[smallest] = heap[i]
			heap[i] = tmp
			i = smallest
	return root


static func _nearest_index(seed: Vector2i) -> int:
	if _cells.is_empty():
		return -1
	var anchor := MapChunks.get_cell_world(seed)
	var best := -1
	var best_dist := INF
	for i in _cells.size():
		var d := anchor.distance_squared_to(_world[i])
		if d < best_dist:
			best_dist = d
			best = i
	return best


# ---------------- 查询 ----------------

static func _index_at(world_pos: Vector2) -> int:
	if not _built:
		return -1
	if world_pos == _at_pos:
		return _at_index
	var index := int(_index.get(MapChunks.world_to_cell(world_pos), -1))
	_at_pos = world_pos
	_at_index = index
	return index


static func _field_for(target: Node2D) -> Field:
	if not _built or _fields.is_empty():
		return null
	if target != null and is_instance_valid(target):
		return _fields.get(target.get_instance_id())
	return _fields.values()[0]


## AI 阵型/攻击锚点：玩家安全孤岛/深 nook 时落在岛外最近安全格，正常时等于玩家格。
static func get_attack_point(target: Node2D) -> Vector2:
	var field := _field_for(target)
	if field != null and field.alive:
		var index := int(_index.get(field.attack_cell, -1))
		if index >= 0:
			return _world[index]
	if target != null and is_instance_valid(target):
		return target_safe_anchor(target)
	return Vector2.ZERO


## 目标点：玩家脚下（根节点 global_position），只夹回地图外边界。
## 不再取撞墙碰撞箱中心/safe 点；贴墙 body-blocked 由 goal_zone 处理。
static func target_anchor(target: Node2D) -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	var point: Vector2 = target.global_position
	if MapBounds != null:
		point = MapBounds.nearest_inside(point, 0.0)
	if not _built and not _ensure_topology():
		return point
	# 脚下贴墙时原点可能落在 solid 格；只在局部找最近“非 solid”格，
	# 不要求 body-safe，避免被拉到远处；贴墙 body-blocked 由 goal_zone 处理。
	var cell := MapChunks.world_to_cell(point)
	if _solid.has(cell):
		var free_index := _nearest_free_cell_local(point, TARGET_SOLID_SNAP_RADIUS)
		if free_index >= 0:
			point = _world[free_index]
	return point


static func _nearest_free_cell_local(point: Vector2, radius_cells: int) -> int:
	var best := -1
	var best_dist := INF
	var max_dist := float(radius_cells) * CELL_SPAN
	var max_sq := max_dist * max_dist
	for i in _cells.size():
		if _solid.has(_cells[i]):
			continue
		var d := _world[i].distance_squared_to(point)
		if d > max_sq:
			continue
		if d < best_dist:
			best_dist = d
			best = i
	return best


## 玩家附近、同一 free 连通域、局部半径内的 body-safe 目标点。
## 不能取全局最近安全格：U 形地形会被开口带到外面。
static func target_safe_anchor(target: Node2D) -> Vector2:
	var point := target_anchor(target)
	if point == Vector2.ZERO:
		return point
	if not _built and not _ensure_topology():
		return point
	var local_walls := _local_wall_component(MapChunks.world_to_cell(point))
	# 优先用 field 预计算的 safe_cell（body_ok 中 dist 最小），查询 O(1)。
	var field := _field_for(target)
	if field != null and field.alive and field.safe_valid:
		var safe_index := int(_index.get(field.safe_cell, -1))
		if safe_index >= 0:
			return _world[safe_index]
	var cell := MapChunks.world_to_cell(point)
	if _cell_body_safe_local(cell, local_walls):
		return point
	var start_cell := cell
	if not _index.has(start_cell) or _solid.has(start_cell):
		start_cell = MapChunks.world_to_cell(target.global_position)
	if not _index.has(start_cell) or _solid.has(start_cell):
		return point
	var best := -1
	var best_dist := INF
	var queue: Array[Vector2i] = [start_cell]
	var depth: Dictionary = {start_cell: 0}
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var d: int = int(depth[cur])
		var index := int(_index.get(cur, -1))
		if index >= 0 and _cell_body_safe_local(cur, local_walls):
			var current_dist := point.distance_squared_to(_world[index])
			if current_dist < best_dist:
				best_dist = current_dist
				best = index
		if d >= TARGET_SAFE_RADIUS:
			continue
		for offset in NEIGHBORS4:
			var next: Vector2i = cur + offset
			if not _index.has(next) or _solid.has(next) or depth.has(next):
				continue
			depth[next] = d + 1
			queue.append(next)
	if best >= 0:
		return _world[best]
	var safe := _nearest_body_safe_in_free_component(start_cell, GOAL_FALLBACK_MAX_CELLS)
	return _world[safe] if safe >= 0 else point


static func target_cell(target: Node2D) -> Vector2i:
	return MapChunks.world_to_cell(target_anchor(target))


static func target_safe_cell(target: Node2D) -> Vector2i:
	return MapChunks.world_to_cell(target_safe_anchor(target))


## 只读：当前 field 的 seed/start/attack/目标格，供寻路场可视化。
static func debug_field(target: Node2D) -> Dictionary:
	var field := _field_for(target)
	if field == null:
		return {}
	return {
		"seed_cell": field.seed_cell,
		"start_cell": field.start_cell,
		"attack_cell": field.attack_cell,
		"target_cell": target_cell(target),
		"target_safe_cell": target_safe_cell(target),
		"target_safe": is_cell_body_safe(target_safe_cell(target), 1),
		"target_solid": _solid.has(target_safe_cell(target)),
		"target_body_safe": is_body_safe(target_safe_anchor(target), 1),
		"alive": field.alive,
		"epoch": epoch,
		"goal_cells": field.goal_zone.keys(),
	}


## 只读：单格的 solid/body-safe/near-solid/dist/flow/goal。
static func debug_cell(target: Node2D, cell: Vector2i) -> Dictionary:
	var field := _field_for(target)
	var index := int(_index.get(cell, -1))
	var world := _world[index] if index >= 0 else MapChunks.get_cell_world(cell)
	var flow := sample(world, target)
	var distance := dist(world, target)
	return {
		"cell": cell,
		"world": world,
		"solid": _solid.has(cell),
		"body_safe": is_cell_body_safe(cell, 1),
		"near_solid": cell_near_solid(index),
		"dist": distance,
		"flow": flow,
		"goal": field != null and field.goal_zone.has(cell),
	}


static func _polyline_length(points: Array) -> float:
	var total := 0.0
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		total += a.distance_to(b)
	return total


## 从玩家口袋边界抽 3~5 条候选 lane；每条 lane 从入口沿 field.dist 走到玩家。
static func route_lanes(target: Node2D, from_pos: Vector2, max_lanes: int = 5) -> Array:
	var field := _field_for(target)
	if field == null or not field.alive:
		return []
	var pocket: Dictionary = field.player_pocket
	if pocket.is_empty():
		pocket = {field.seed_cell: true}
	var entries: Array[Vector2i] = []
	for cell in pocket:
		var boundary := false
		for offset in NEIGHBORS4:
			var n: Vector2i = cell + offset
			if not pocket.has(n) and _index.has(n) and not _solid.has(n):
				boundary = true
				break
		if boundary:
			entries.append(cell)
	if entries.is_empty():
		entries.append(field.seed_cell)
	var seen: Dictionary = {}
	var lanes: Array = []
	for cell in entries:
		if seen.has(cell):
			continue
		seen[cell] = true
		var entry_world: Vector2 = MapChunks.get_cell_world(cell)
		var points := route_points(target, entry_world)
		if points.size() < 2:
			continue
		var idx := int(_index.get(cell, -1))
		lanes.append({
			"entry": entry_world,
			"points": points,
			"dist": field.dist[idx] if idx >= 0 else INF,
			"length": _polyline_length(points),
		})
		if lanes.size() >= max_lanes:
			break
	return lanes


## 从 from_pos 沿 field.dist 下降方向抽一条近似路线到 target（玩家）。
## 只取每 step_cells 格一个 waypoint；供敌人做参考，不要求沿格心走。
static func route_points(target: Node2D, from_pos: Vector2, step_cells: int = 1) -> Array:
	var field := _field_for(target)
	if field == null or not field.alive:
		return []
	var cur := _index_at(from_pos)
	if cur < 0:
		cur = _nearest_index(MapChunks.world_to_cell(from_pos))
	if cur < 0:
		return []
	var out: Array = []
	var guard := 0
	var step_dist := float(step_cells) * CELL_SPAN
	while cur >= 0 and guard < 500:
		if out.is_empty() or out[out.size() - 1].distance_to(_world[cur]) >= step_dist:
			out.append(_world[cur])
		var next := _route_next(field, cur)
		if next < 0 or next == cur:
			break
		cur = next
		guard += 1
	if not out.is_empty():
		out.append(_world[cur])
	return out


static func _route_next(field: Field, cur: int) -> int:
	var cell: Vector2i = _cells[cur]
	var best := -1
	var best_dist: float = field.dist[cur]
	for offset in NEIGHBORS8:
		var next_cell: Vector2i = cell + offset
		var next_index: int = int(_index.get(next_cell, -1))
		if next_index < 0 or not _flow_passable(next_index, field.goal_zone, field.local_walls, field):
			continue
		var off: Vector2i = offset
		if not simple_field_mode and not _diagonal_ok(cell, off, field.goal_zone, field.local_walls, field):
			continue
		if field.dist[next_index] < best_dist - 0.0001:
			best_dist = field.dist[next_index]
			best = next_index
	return best


## 只读：全图格子快照（729 格），供 overlay 画 dense flow。
static func debug_field_cells(target: Node2D) -> Array:
	var field := _field_for(target)
	var out: Array = []
	for i in _cells.size():
		var cell: Vector2i = _cells[i]
		out.append({
			"cell": cell,
			"world": _world[i],
			"solid": _solid.has(cell),
			"body_safe": is_cell_body_safe(cell, 1),
			"near_solid": cell_near_solid(i),
			"dist": field.dist[i] if field != null and i < field.dist.size() else INF,
			"flow": field.flow[i] if field != null and i < field.flow.size() else Vector2.ZERO,
			"goal": field != null and field.goal_zone.has(cell),
		})
	return out


static func _find_wall_body(node: Node) -> PhysicsBody2D:
	if node is PhysicsBody2D:
		var body := node as PhysicsBody2D
		if (body.collision_mask & WALL_LAYER) != 0:
			return body
	for child in node.get_children():
		var found := _find_wall_body(child)
		if found != null:
			return found
	return null


static func _wall_body_shapes(body: PhysicsBody2D) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for child in body.get_children():
		if child is CollisionShape2D:
			var shape := child as CollisionShape2D
			if not shape.disabled:
				out.append(shape)
		elif child is CollisionPolygon2D:
			var poly := child as CollisionPolygon2D
			if not poly.disabled:
				out.append(poly)
	return out


## 玩家是否与 from_pos 的敌人处于同一 body-safe 连通域。
## 不能用 attack 格中心与玩家世界坐标的距离：格心/预测提前量会造成空旷地误判。
static func is_target_reachable_from(target: Node2D, from_pos: Vector2) -> bool:
	if not complex_path_enabled:
		# 非壁垒场景没有场：默认视为可达，走直连/决策。
		return true
	if target == null or not is_instance_valid(target):
		return false
	var player_cell := target_safe_cell(target)
	if not is_cell_body_safe(player_cell, 1):
		return false
	var from_cell := MapChunks.world_to_cell(from_pos)
	var from_index := int(_index.get(from_cell, -1))
	if from_index < 0 or not is_cell_body_safe(from_cell, 1):
		from_index = _nearest_body_safe_index(from_pos)
	if from_index < 0:
		return false
	from_cell = _cells[from_index]
	# 快速路径：流场 dist 有限 ⇒ 该格与 seed 在同一 passable 连通域 ⇒ 视为可达（O(1)）。
	# from_cell 已过 is_cell_body_safe，因此"有限 ⇒ 可达"是保守正确的。
	var field := _field_for(target)
	if field != null:
		if from_index < field.dist.size() and field.dist[from_index] < INF:
			return true
		if field.player_component_cell != player_cell:
			field.player_component = _body_safe_component(player_cell)
			field.player_component_cell = player_cell
		return field.player_component.has(from_cell)
	var component := _body_safe_component(player_cell)
	return component.has(from_cell)


# ---------------- 按格索引快速查询（调用方自己换格一次，避免重复 world_to_cell） ----------------

static func cell_index(cell: Vector2i) -> int:
	return int(_index.get(cell, -1))


# 格心到可行走边界的余量（px）。一次性算好，槽点校验不再逐次做 polygon 判定。
static func cell_clearance(index: int) -> float:
	if index < 0 or index >= _clearance.size():
		return 0.0
	return _clearance[index]


# 格心到可行走边界的余量（px）。
# 拓扑期 hull 必为凸多边形（walls 四向射线），而「nearest_inside(center, r) == center」
# 对凸多边形等价于「点到边界距离 >= r」→ 直接算点到各边的最小距离，
# 替代原来每格 8 次二分（8 × O(边数) × 729 次是开局尖峰的主项）。
static func _measure_clearance(center: Vector2, hull: PackedVector2Array) -> float:
	var n := hull.size()
	if n < 3:
		return 0.0
	if not _point_in_polygon_fast(center, hull):
		return 0.0
	var best := 1e9
	for i in n:
		var d := _point_segment_distance(center, hull[i], hull[(i + 1) % n])
		if d < best:
			best = d
	return clampi(best, 0.0, 320.0)


# 与 MapBounds._point_in_polygon 同算法（绕序无关的射线法）。
static func _point_in_polygon_fast(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var a := poly[i]
		var b := poly[j]
		if (a.y > p.y) != (b.y > p.y):
			if p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
				inside = not inside
		j = i
	return inside


# 该格 8 邻域（含自身）是否有阻挡格：有就说明"附近可能有墙/阻挡"，不能走快速放行
static func cell_near_solid(index: int) -> bool:
	return index >= 0 and index < _near_solid.size() and _near_solid[index] == 1


# 该格离墙余量是否够站人（预计算表，O(1)）
static func cell_margin_ok(index: int) -> bool:
	return index >= 0 and index < _margin_ok.size() and _margin_ok[index] == 1


static func is_cell_solid(cell: Vector2i) -> bool:
	return _solid.has(cell)


# 返回该格到目标的场距离；<0 表示"未知/无场"（调用方按放行处理），INF 表示不可达
static func cell_dist(index: int, target: Node2D) -> float:
	var field := _field_for(target)
	if field == null or not field.alive or index < 0:
		return -1.0
	if index >= field.dist.size():
		return -1.0
	return field.dist[index]


static func sample(world_pos: Vector2, target: Node2D = null) -> Vector2:
	var field := _field_for(target)
	if field == null or not field.alive:
		return Vector2.ZERO
	var index := _index_at(world_pos)
	if index < 0:
		return Vector2.ZERO
	return field.flow[index]


static func dist(world_pos: Vector2, target: Node2D = null) -> float:
	var field := _field_for(target)
	if field == null or not field.alive:
		return INF
	var index := _index_at(world_pos)
	if index < 0:
		return INF
	return field.dist[index]


# 该世界点是否不可通行（不在可行走格，或落在阻挡集里）
static func is_solid(world_pos: Vector2) -> bool:
	if not _built:
		return false
	var index := _index_at(world_pos)
	if index < 0:
		return true
	return _solid.has(_cells[index])


# 身体安全：格心本身非阻挡，且墙面余量 >= BODY_CLEARANCE。
# 一格宽通道 clearance≈32，可通过；真正窄缝 <16 仍会挡。
static func is_cell_body_safe(cell: Vector2i, clearance_cells: int = 1) -> bool:
	var index := int(_index.get(cell, -1))
	if index < 0 or index >= _cells.size():
		return false
	if _solid.has(cell):
		return false
	if clearance_cells <= 0:
		return true
	if index < _wall_clearance.size():
		return _wall_clearance[index] >= BODY_CLEARANCE
	return _near_solid[index] == 0


## 玩家脚下格 8 邻域 solid 的连通块（4 邻接）。
static func _local_wall_component(seed: Vector2i) -> Dictionary:
	var local: Dictionary = {}
	var queue: Array[Vector2i] = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var c := seed + Vector2i(dx, dy)
			if _solid.has(c):
				queue.append(c)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		if local.has(cur):
			continue
		local[cur] = true
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				if dx == 0 and dy == 0:
					continue
				var n := cur + Vector2i(dx, dy)
				if _solid.has(n) and not local.has(n):
					queue.append(n)
	return local


## 玩家脚下相连的 free 口袋（4 邻接，限格数）。
static func _player_pocket_cells(seed: Vector2i) -> Dictionary:
	var pocket: Dictionary = {}
	var queue: Array[Vector2i] = [seed]
	var head := 0
	while head < queue.size() and pocket.size() < PLAYER_POCKET_MAX_CELLS:
		var cur: Vector2i = queue[head]
		head += 1
		if pocket.has(cur):
			continue
		if not _index.has(cur) or _solid.has(cur):
			continue
		pocket[cur] = true
		for offset in NEIGHBORS4:
			var next: Vector2i = cur + offset
			if _index.has(next) and not _solid.has(next) and not pocket.has(next):
				queue.append(next)
	return pocket


## 局部 body-safe：默认 clearance；玩家相连墙的 near-solid 不计入。
static func _cell_body_safe_local(cell: Vector2i, local_walls: Dictionary) -> bool:
	var index := int(_index.get(cell, -1))
	if index < 0 or index >= _cells.size():
		return false
	if _solid.has(cell):
		return false
	if local_walls.is_empty():
		return is_cell_body_safe(cell, 1)
	if index < _wall_clearance.size():
		if _wall_clearance[index] >= BODY_CLEARANCE:
			return true
		# 最近墙不是玩家相连墙 → 不可能靠 local_walls 放宽，直接 false，免全扫。
		if index < _wall_nearest.size() and not local_walls.has(_wall_nearest[index]):
			return false
	return _wall_clearance_excluding(index, local_walls) >= BODY_CLEARANCE


static func _wall_clearance_excluding(index: int, local_walls: Dictionary) -> float:
	if index < 0 or index >= _cells.size():
		return 0.0
	var center: Vector2 = _world[index]
	var best := 1000.0
	# 先扫邻块；若最近非 local 墙仍 >= 阈值，再扩一圈确认（排除玩家相连墙后可能更远）。
	for radius in [1, 2]:
		for cell in _nearby_solid_cells(_cells[index], radius):
			if local_walls.has(cell):
				continue
			var c: Vector2 = _world[int(_index[cell])] if _index.has(cell) else MapChunks.get_cell_world(cell)
			var corners: Array = [
				c + Vector2(0, 0),
				c + Vector2(-32, -16),
				c + Vector2(0, -32),
				c + Vector2(32, -16),
			]
			for i in 4:
				var a: Vector2 = corners[i]
				var b: Vector2 = corners[(i + 1) % 4]
				var d := _point_segment_distance(center, a, b)
				if d < best:
					best = d
		if best < BODY_CLEARANCE:
			return best
	return best


static func is_body_safe(world_pos: Vector2, clearance_cells: int = 1) -> bool:
	if not _built:
		# 场未建好时不阻断旧行为；调用方负责先 ensure_topology()。
		return true
	var index := _index_at(world_pos)
	if index < 0:
		return false
	return is_cell_body_safe(_cells[index], clearance_cells)


# 最近的 body-safe 世界点：用于刷怪兜底、卡进障碍格后的逃逸。
# 低频路径，O(cells)；找不到时回退 MapBounds.nearest_inside。
static func nearest_body_safe_point(world_pos: Vector2, clearance_cells: int = 1) -> Vector2:
	if not _built and not _ensure_topology():
		return MapBounds.nearest_inside(world_pos, 24.0)
	var index := _index_at(world_pos)
	if index >= 0 and is_cell_body_safe(_cells[index], clearance_cells):
		return world_pos
	# 按「起始格 + clearance」缓存：卡墙敌人每帧查询同一点，避免每次全扫 729 格。
	var cache_key := Vector2i(index, clearance_cells)
	if index >= 0 and _safe_point_cache.has(cache_key):
		return _safe_point_cache[cache_key]
	var best_sq := INF
	var best_pos := world_pos
	for i in _cells.size():
		if not is_cell_body_safe(_cells[i], clearance_cells):
			continue
		var d := _world[i].distance_squared_to(world_pos)
		if d < best_sq:
			best_sq = d
			best_pos = _world[i]
	if best_sq < INF:
		if index >= 0:
			if _safe_point_cache.size() >= 128:
				_safe_point_cache.clear()
			_safe_point_cache[cache_key] = best_pos
		return best_pos
	return MapBounds.nearest_inside(world_pos, 24.0)


# 医疗包等拾取物的安全落点：先夹回地图外边界，再避开 NavObstacle solid。
# 无墙时零开销；有墙但找不到安全点时返回 Vector2.INF，由调用方跳过生成。
static func safe_pickup_point(world_pos: Vector2) -> Vector2:
	if not world_pos.is_finite():
		return Vector2.INF
	var pos := MapBounds.nearest_inside(world_pos, 24.0)
	if not _built and not has_blocks():
		return pos
	if not _ensure_topology():
		return pos
	if not is_solid(pos):
		return pos
	var safe := nearest_body_safe_point(pos, 1)
	if safe.is_finite() and not is_solid(safe):
		return safe
	return Vector2.INF
