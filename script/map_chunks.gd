extends Node

const DEFAULT_CHUNK_SIZE := Vector2i(4, 4)
const DEFAULT_MIN_RATIO := 0.5
const TERRAIN_INSET_PX := 8.0
const INVALID_CELL := Vector2i(2147483647, 2147483647)

var _tilemap: Node
var _map_instance_id: int = 0
var _hull_signature: int = 0
var _built := false
var _warned_boundary_source := false
var _all_cells: Array[Vector2i] = []
var _cell_set: Dictionary = {}
var _spawnable_cells: Dictionary = {}
var _portal_cells: Dictionary = {}
var _grids: Dictionary = {}
var _reserved_cells: Dictionary = {}
var _side_anchors: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _side_anchor_valid: Array[bool] = [false, false, false, false]

func _ready() -> void:
	GameEvents.first_round_add.connect(invalidate)

func invalidate() -> void:
	_tilemap = null
	_map_instance_id = 0
	_hull_signature = 0
	_built = false
	_all_cells.clear()
	_cell_set.clear()
	_spawnable_cells.clear()
	_portal_cells.clear()
	_grids.clear()
	_reserved_cells.clear()
	_side_anchors = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	_side_anchor_valid = [false, false, false, false]
	# 地图拓扑变化 → 敌人导航场必须重建（它缓存了格子图与距离场）。
	EnemyNavField.invalidate()

func ensure_ready() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var map := tree.get_first_node_in_group("Map")
	if map == null or not is_instance_valid(map) or not map.has_method("get_used_cells"):
		return false
	MapBounds.ensure_ready()
	var hull := MapBounds.get_walkable_polygon()
	if hull.size() < 3:
		return false
	var map_id := map.get_instance_id()
	var signature := _poly_signature(hull)
	if _built and _map_instance_id == map_id and _hull_signature == signature:
		return not _all_cells.is_empty()
	_build(tree, map, hull)
	return _built and not _all_cells.is_empty()

func get_all_cells() -> Array[Vector2i]:
	if not ensure_ready():
		return []
	return _all_cells.duplicate()

func get_walkable_polygon() -> PackedVector2Array:
	if not ensure_ready():
		return PackedVector2Array()
	return MapBounds.get_walkable_polygon()

func get_grid(chunk_size: Vector2i) -> MapChunkGrid:
	if not ensure_ready():
		return null
	var key := Vector2i(maxi(1, chunk_size.x), maxi(1, chunk_size.y))
	if _grids.has(key):
		return _grids[key]
	var grid := MapChunkGrid.new(key)
	grid.build(_all_cells, Callable(self, "_cell_world_for_grid"), _spawnable_cells, _portal_cells)
	_grids[key] = grid
	return grid

func get_chunks(chunk_size: Vector2i = DEFAULT_CHUNK_SIZE, min_ratio: float = DEFAULT_MIN_RATIO) -> Array[MapChunk]:
	var grid := get_grid(chunk_size)
	if grid == null:
		return []
	return grid.get_chunks(min_ratio)

func pick_chunks(chunk_size: Vector2i, count: int, exclude_cells: Array = [], min_ratio: float = DEFAULT_MIN_RATIO, rng: RandomNumberGenerator = null, allow_reserved: bool = false, allow: Callable = Callable()) -> Array[MapChunk]:
	var grid := get_grid(chunk_size)
	if grid == null:
		return []
	var exclude: Array = exclude_cells.duplicate()
	if not allow_reserved:
		exclude.append_array(get_reserved_cells())
	return grid.pick_chunks(count, exclude, min_ratio, rng, allow)

func get_chunk_cells(chunk: MapChunk) -> Array[Vector2i]:
	if chunk == null:
		return []
	return chunk.cells.duplicate()

func world_to_cell(world_pos: Vector2) -> Vector2i:
	if not _built and not ensure_ready():
		return INVALID_CELL
	return _world_to_cell(_tilemap, world_pos)

func get_cell_world(cell: Vector2i) -> Vector2:
	if not _built and not ensure_ready():
		return Vector2.ZERO
	return _cell_world(_tilemap, cell)

func cell_to_chunk(cell: Vector2i, chunk_size: Vector2i = DEFAULT_CHUNK_SIZE) -> Vector2i:
	var grid := get_grid(chunk_size)
	if grid == null:
		return Vector2i(2147483647, 2147483647)
	return grid.cell_to_chunk(cell)

func is_spawnable_cell(cell: Vector2i) -> bool:
	if not _built and not ensure_ready():
		return false
	return _spawnable_cells.has(cell)

func is_portal_cell(cell: Vector2i) -> bool:
	if not _built and not ensure_ready():
		return false
	return _portal_cells.has(cell)

func reserve_cells(source_id: String, cells: Array) -> void:
	release_cells(source_id)
	var unique: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cell in cells:
		if cell is Vector2i and not seen.has(cell):
			seen[cell] = true
			unique.append(cell)
	_reserved_cells[source_id] = unique

func release_cells(source_id: String) -> void:
	_reserved_cells.erase(source_id)

func get_reserved_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cells in _reserved_cells.values():
		for cell in cells:
			if cell is Vector2i and not seen.has(cell):
				seen[cell] = true
				out.append(cell)
	return out

func get_side_anchor(side: int) -> Vector2:
	if side < 0 or side >= _side_anchors.size():
		return Vector2.ZERO
	return _side_anchors[side]

func is_side_anchor_valid(side: int) -> bool:
	if side < 0 or side >= _side_anchor_valid.size():
		return false
	return _side_anchor_valid[side]

func get_boundary_source() -> StringName:
	if not ensure_ready():
		return &""
	return MapBounds.get_boundary_source()

func _build(tree: SceneTree, map: Node, hull: PackedVector2Array) -> void:
	_all_cells.clear()
	_cell_set.clear()
	_spawnable_cells.clear()
	_portal_cells.clear()
	_grids.clear()
	_reserved_cells.clear()
	_side_anchors = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	_side_anchor_valid = [false, false, false, false]
	_tilemap = map
	_map_instance_id = map.get_instance_id()
	_hull_signature = _poly_signature(hull)
	_built = false
	var source := MapBounds.get_boundary_source()
	if source == &"walls":
		_warned_boundary_source = false
	elif not _warned_boundary_source:
		_warned_boundary_source = true
		push_warning("MapChunks: MapBounds boundary source is '%s'; terrain chunks may only cover the spawn-safe area." % source)
	var inset := _inset_polygon(hull, TERRAIN_INSET_PX)
	if inset.size() < 3:
		inset = hull
	_cache_map_cells(tree, map)
	var min_cell := INVALID_CELL
	var max_cell := Vector2i(-2147483647, -2147483647)
	for point in inset:
		var cell := _world_to_cell(map, point)
		if cell == INVALID_CELL:
			continue
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	if min_cell == INVALID_CELL:
		_built = true
		return
	for x in range(min_cell.x - 1, max_cell.x + 2):
		for y in range(min_cell.y - 1, max_cell.y + 2):
			var cell := Vector2i(x, y)
			var world_center := _cell_world(map, cell)
			if not Geometry2D.is_point_in_polygon(world_center, inset):
				continue
			if _cell_set.has(cell):
				continue
			_cell_set[cell] = true
			_all_cells.append(cell)
	_all_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x == b.x:
			return a.y < b.y
		return a.x < b.x
	)
	_built = true

func _cache_map_cells(tree: SceneTree, map: Node) -> void:
	var cells: Array = map.get_used_cells(0)
	for cell in cells:
		if cell is Vector2i:
			_spawnable_cells[cell] = true
	var group_names := ["North", "East", "South", "West"]
	for side in group_names.size():
		var portal := tree.get_first_node_in_group(group_names[side])
		if portal == null or not is_instance_valid(portal) or not portal.has_method("get_used_cells"):
			continue
		var portal_cells: Array = portal.get_used_cells(0)
		var anchor_sum := Vector2.ZERO
		var anchor_count := 0
		for cell in portal_cells:
			if cell is Vector2i:
				_portal_cells[cell] = true
				anchor_sum += _cell_world(map, cell)
				anchor_count += 1
		if anchor_count > 0:
			_side_anchors[side] = anchor_sum / float(anchor_count)
			_side_anchor_valid[side] = true

func _cell_world_for_grid(cell: Vector2i) -> Vector2:
	return _cell_world(_tilemap, cell)

func _world_to_cell(map: Node, world_pos: Vector2) -> Vector2i:
	if map == null or not (map is Node2D) or not map.has_method("local_to_map"):
		return INVALID_CELL
	var local := (map as Node2D).to_local(world_pos)
	var cell = map.call("local_to_map", local)
	if cell is Vector2i:
		return cell
	return INVALID_CELL

func _cell_world(map: Node, cell: Vector2i) -> Vector2:
	if map == null or not (map is Node2D) or not map.has_method("map_to_local"):
		return Vector2.ZERO
	var local = map.call("map_to_local", cell)
	if local is Vector2:
		return (map as Node2D).to_global(local)
	return Vector2.ZERO

func _inset_polygon(poly: PackedVector2Array, amount: float) -> PackedVector2Array:
	if amount <= 0.0:
		return poly
	var result := Geometry2D.offset_polygon(poly, -amount, Geometry2D.JOIN_MITER)
	for candidate in result:
		if candidate.size() >= 3:
			return candidate
	return poly

func _poly_signature(poly: PackedVector2Array) -> int:
	var value := 17
	for point in poly:
		value = (value * 31 + int(round(point.x * 100.0))) ^ int(round(point.y * 100.0))
	return value
