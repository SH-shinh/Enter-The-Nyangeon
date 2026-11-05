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
const MAX_FIELDS := 2
const WALL_LAYER := 256
const OBSTACLE_INFLATE := 28.0
const SCAN_MAX_DEPTH := 32

const NEIGHBORS4 := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

class Field:
	var seed_cell: Vector2i = Vector2i.ZERO
	var dist := PackedFloat32Array()
	var flow := PackedVector2Array()
	var alive: bool = false
	var built_ms: int = 0

static var _built: bool = false
static var _sig: int = 0
static var _cells: Array[Vector2i] = []
static var _index: Dictionary = {}
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
# 每格 8 邻域是否含阻挡格（用于墙探针的快速放行）
static var _near_solid := PackedByteArray()
# 格内任意点到格心的最大距离（64×32 格的半对角 35.8，留 1px 余量）
const CELL_SPAN := 37.0

static var _fields: Dictionary = {}
# 场版本号：每次重建/清空 +1。敌人用它判断"场流采样结果还能不能复用"。
static var epoch: int = 0


# ---------------- 阻挡注册 ----------------

static func has_blocks() -> bool:
	return not _block_counts.is_empty()


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
	_clear_fields()


static func is_ready(target: Node2D = null) -> bool:
	if not _built:
		return false
	if _fields.is_empty():
		return false
	if target == null:
		return true
	var field: Field = _fields.get(target.get_instance_id())
	return field != null and field.alive


static func _clear_fields() -> void:
	_fields.clear()
	epoch += 1


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
	var cells := MapChunks.get_all_cells()
	_built = false
	_sig = sig
	_cells = cells
	_index.clear()
	_world = PackedVector2Array()
	_world.resize(_cells.size())
	_margin_ok.resize(_cells.size())
	_clearance.resize(_cells.size())
	for i in _cells.size():
		_index[_cells[i]] = i
		_world[i] = MapChunks.get_cell_world(_cells[i])
		var margin := MapBounds.nearest_inside(_world[i], SLOT_MARGIN)
		_margin_ok[i] = 1 if margin == _world[i] else 0
		_clearance[i] = _measure_clearance(_world[i])
	_scan_static_obstacles()
	_rebuild_solid()
	_clear_fields()
	_built = not _cells.is_empty()


static func _rebuild_solid() -> void:
	_solid.clear()
	for cell in _solid_auto:
		_solid[cell] = true
	for cell in _block_counts:
		_solid[cell] = true
	# 8 邻域阻挡表（墙探针的快速放行用；必须随 _solid 一起刷新）
	_near_solid.resize(_cells.size())
	for i in _cells.size():
		var origin := _cells[i]
		var hit := _solid.has(origin)
		if not hit:
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					if _solid.has(origin + Vector2i(dx, dy)):
						hit = true
						break
				if hit:
					break
		_near_solid[i] = 1 if hit else 0


# ---------------- 自动障碍扫描 ----------------

static func _scan_static_obstacles() -> void:
	_solid_auto.clear()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var root := tree.current_scene
	if root == null:
		return
	_scan_node(root, 0)


static func _scan_node(node: Node, depth: int) -> void:
	if node is StaticBody2D:
		var body := node as StaticBody2D
		if (body.collision_layer & WALL_LAYER) != 0:
			_mark_static_body(body)
	if depth >= SCAN_MAX_DEPTH:
		return
	for child in node.get_children():
		_scan_node(child, depth + 1)


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
	for i in _cells.size():
		if grown.has_point(_world[i]):
			_solid_auto[_cells[i]] = true


# ---------------- 场构建 ----------------

static func ensure_rebuilt(target: Node2D, anchor: Vector2 = Vector2.ZERO) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not _ensure_topology():
		return false
	var key := target.get_instance_id()
	var base_point: Vector2 = anchor if anchor != Vector2.ZERO else target.global_position
	var seed: Vector2i = MapChunks.world_to_cell(base_point)
	# 预判点若落在障碍格里，退回目标自身所在格（不把场种在墙上）
	if _solid.has(seed):
		seed = MapChunks.world_to_cell(target.global_position)
	var field: Field = _fields.get(key)
	if field != null and field.alive and field.seed_cell == seed:
		return true
	if field == null:
		if _fields.size() >= MAX_FIELDS:
			_evict_one()
		field = Field.new()
		_fields[key] = field
	_rebuild_field(field, seed)
	return field.alive


static func _evict_one() -> void:
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


static func _rebuild_field(field: Field, seed: Vector2i) -> void:
	var n := _cells.size()
	if n <= 0:
		field.alive = false
		return
	field.dist.resize(n)
	field.flow.resize(n)
	for i in n:
		field.dist[i] = INF
		field.flow[i] = Vector2.ZERO
	var start: int = int(_index.get(seed, -1))
	if start < 0:
		start = _nearest_index(seed)
	if start < 0:
		field.alive = false
		return
	field.seed_cell = seed
	field.dist[start] = 0.0
	var queue: Array[int] = [start]
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		var cur_dist: float = field.dist[cur]
		var cur_cell: Vector2i = _cells[cur]
		for offset in NEIGHBORS4:
			var next_cell: Vector2i = cur_cell + offset
			var next_index: int = int(_index.get(next_cell, -1))
			if next_index < 0 or _solid.has(next_cell):
				continue
			if cur_dist + 1.0 < field.dist[next_index]:
				field.dist[next_index] = cur_dist + 1.0
				queue.append(next_index)
	for i in n:
		var cell: Vector2i = _cells[i]
		var best := -1
		var best_dist: float = field.dist[i]
		for offset in NEIGHBORS4:
			var next_cell: Vector2i = cell + offset
			var next_index: int = int(_index.get(next_cell, -1))
			if next_index < 0 or _solid.has(next_cell):
				continue
			if field.dist[next_index] < best_dist:
				best_dist = field.dist[next_index]
				best = next_index
		if best < 0:
			continue
		var direction: Vector2 = _world[best] - _world[i]
		if direction.length_squared() > 0.0001:
			field.flow[i] = direction.normalized()
	field.alive = true
	field.built_ms = Time.get_ticks_msec()
	epoch += 1


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
	return int(_index.get(MapChunks.world_to_cell(world_pos), -1))


static func _field_for(target: Node2D) -> Field:
	if not _built or _fields.is_empty():
		return null
	if target != null and is_instance_valid(target):
		return _fields.get(target.get_instance_id())
	return _fields.values()[0]


# ---------------- 按格索引快速查询（调用方自己换格一次，避免重复 world_to_cell） ----------------

static func cell_index(cell: Vector2i) -> int:
	return int(_index.get(cell, -1))


# 格心到可行走边界的余量（px）。一次性算好，槽点校验不再逐次做 polygon 判定。
static func cell_clearance(index: int) -> float:
	if index < 0 or index >= _clearance.size():
		return 0.0
	return _clearance[index]


# 二分求余量：nearest_inside(center, r) == center ⟺ 余量 >= r
static func _measure_clearance(center: Vector2) -> float:
	if MapBounds.nearest_inside(center, 0.0) != center:
		return 0.0
	var lo := 0.0
	var hi := 320.0
	for i in 8:
		var mid := (lo + hi) * 0.5
		if MapBounds.nearest_inside(center, mid) == center:
			lo = mid
		else:
			hi = mid
	return lo


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
