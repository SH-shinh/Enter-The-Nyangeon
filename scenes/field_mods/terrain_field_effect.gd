class_name TerrainFieldEffect
extends FieldModEffect

@export_group("Chunks")
@export var chunk_size: Vector2i = Vector2i(4, 4)
@export var chunk_count: int = 3
@export_range(0.0, 1.0) var chunk_ratio: float = 0.0
@export var min_walkable_ratio: float = 0.5
@export var avoid_portal_chunks: bool = true
@export var avoid_spawnable_chunks: bool = false
@export var avoid_player_start_radius: float = 0.0
@export var allow_overlap: bool = false

@export_group("Overlay")
@export var overlay_tile_set: TileSet
@export var overlay_source_id: int = 0
@export var overlay_atlas_coords: Vector2i = Vector2i.ZERO
@export var overlay_color: Color = Color(1.0, 1.0, 1.0, 0.35)
@export var overlay_z_index: int = -1

@export_group("Timing")
@export var tick_interval: int = 5
@export var duration_ticks: int = 0

@export_group("Movement blocking")
## 勾选后这些格子会注册进 EnemyNavField，敌人 AI 会绕行（默认关闭 → 现有词条零变化）。
@export var blocks_movement: bool = false
## true = 阻挡格由场景里的 NavObstacle TileMapLayer 直接生成，不再走 add_block。
## 适用于壁垒这种“视觉/碰撞都是 TileMapLayer”的场地；tilemap cells 变化后由 on_start/on_stop invalidate。
@export var nav_use_obstacle_tilemap: bool = false
## 只对 blocks_movement 生效：避开场地中央的 Boss 刷新锚点（塔/Goliath 没有寻路，不能被围死）。
@export var avoid_center_radius: float = 240.0

const NEIGHBOR_OFFSETS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

var chunks: Array[MapChunk] = []

var _grid: MapChunkGrid
var _cells: Dictionary = {}
var _overlay: TileMapLayer
var _reserved_source_id := ""
var _tick_count := 0

func on_start() -> void:
	if chunk_count <= 0 and chunk_ratio <= 0.0:
		finish()
		return
	_reserved_source_id = "terrain:%d" % get_instance_id()
	_grid = MapChunks.get_grid(chunk_size)
	if _grid == null:
		push_warning("TerrainFieldEffect: MapChunks is not ready")
		finish()
		return
	chunks = _pick_terrain_chunks()
	if blocks_movement and not chunks.is_empty():
		# 阻挡类词条必须保证不会把可行走区域封死（Boss / 刷怪 portal 都要留着通路）。
		chunks.assign(_filter_connected_chunks(chunks))
	if chunks.is_empty():
		push_warning("TerrainFieldEffect: no eligible chunks")
		finish()
		return
	if not allow_overlap:
		MapChunks.reserve_cells(_reserved_source_id, _reservation_cells())
	for chunk in chunks:
		for cell in chunk.cells:
			_cells[cell] = true
	if blocks_movement and not nav_use_obstacle_tilemap:
		EnemyNavField.add_block(_reserved_source_id, get_terrain_cells())
	_build_overlay()
	# tilemap 模式：cells 刚由 _build_overlay() 填好，失效一次让下次查询重新扫描 NavObstacle。
	if blocks_movement and nav_use_obstacle_tilemap:
		EnemyNavField.invalidate()
	_tick_count = 0
	on_terrain_start()

func on_stop() -> void:
	on_terrain_stop()
	if _reserved_source_id != "" and not nav_use_obstacle_tilemap:
		EnemyNavField.remove_block(_reserved_source_id)
	if _overlay != null and is_instance_valid(_overlay):
		# 先脱离 NavObstacle 组，避免 queue_free 延迟期间场重建仍扫到旧墙。
		if blocks_movement and nav_use_obstacle_tilemap:
			_overlay.remove_from_group(EnemyNavField.OBSTACLE_GROUP)
		_overlay.queue_free()
	_overlay = null
	if blocks_movement and nav_use_obstacle_tilemap:
		# 层释放后再失效，下一次查询不会把已删除的障碍 tilemap 算进去。
		EnemyNavField.invalidate()
	if _reserved_source_id != "" and not allow_overlap:
		MapChunks.release_cells(_reserved_source_id)
	_reserved_source_id = ""
	_grid = null
	_cells.clear()
	chunks.clear()
	_tick_count = 0

func _pick_terrain_chunks() -> Array[MapChunk]:
	if _grid == null:
		return []
	var count := chunk_count
	if chunk_ratio > 0.0:
		var available := _grid.get_chunks(min_walkable_ratio)
		count = maxi(1, int(ceil(float(available.size()) * chunk_ratio)))
	var exclude: Array = [] if allow_overlap else MapChunks.get_reserved_cells()
	var player := _find_player()
	return _grid.pick_chunks(
		count,
		exclude,
		min_walkable_ratio,
		null,
		func(chunk: MapChunk) -> bool: return _allow_chunk(chunk, player)
	)

func _reservation_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for chunk in chunks:
		out.append_array(chunk.cells)
	return out

func on_tick() -> void:
	_tick_count += 1
	if duration_ticks > 0 and _tick_count >= duration_ticks:
		finish()
		return
	if tick_interval > 1 and _tick_count % tick_interval != 0:
		return
	on_terrain_tick()

func get_terrain_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in _cells.keys():
		if cell is Vector2i:
			out.append(cell)
	return out

func get_terrain_source_id() -> String:
	return _reserved_source_id

func get_overlay() -> TileMapLayer:
	return _overlay

func is_body_in_terrain(body: Node2D) -> bool:
	if body == null or not is_instance_valid(body) or not body.is_inside_tree():
		return false
	return _cells.has(MapChunks.world_to_cell(body.global_position))

func on_terrain_start() -> void:
	pass

func on_terrain_stop() -> void:
	pass

func on_terrain_tick() -> void:
	pass

func _build_overlay() -> void:
	if overlay_tile_set == null:
		return
	_overlay = TileMapLayer.new()
	_overlay.name = "TerrainOverlay"
	_overlay.tile_set = overlay_tile_set
	_overlay.z_index = overlay_z_index
	_overlay.modulate = overlay_color
	_overlay.y_sort_enabled = false
	add_child(_overlay)
	for cell in _cells.keys():
		if cell is Vector2i:
			_overlay.set_cell(cell, overlay_source_id, overlay_atlas_coords)

func _find_player() -> Node2D:
	var player := get_tree().get_first_node_in_group("Player")
	return player as Node2D

func _allow_chunk(chunk: MapChunk, player: Node2D) -> bool:
	if chunk == null:
		return false
	if avoid_portal_chunks and chunk.portal_cell_count > 0:
		return false
	if avoid_spawnable_chunks and chunk.spawnable_cell_count > 0:
		return false
	if avoid_player_start_radius > 0.0 and player != null and is_instance_valid(player):
		for cell in chunk.cells:
			if MapChunks.get_cell_world(cell).distance_to(player.global_position) < avoid_player_start_radius:
				return false
	if blocks_movement and avoid_center_radius > 0.0:
		var center := get_tree().get_first_node_in_group("CenterPosition")
		if center is Node2D:
			var center_pos := (center as Node2D).global_position
			for cell in chunk.cells:
				if MapChunks.get_cell_world(cell).distance_to(center_pos) < avoid_center_radius:
					return false
	return true

# ---------------- 阻挡类词条：连通性保证 ----------------
# 逐个尝试加入块；只要会把"原本能走到的区域"封死就丢弃该块。
# 这样 Boss（没有寻路）与刷怪 portal 不会被障碍彻底隔断。
func _filter_connected_chunks(source_chunks: Array) -> Array:
	var all_cells := MapChunks.get_all_cells()
	if all_cells.is_empty():
		return source_chunks
	var baseline := _reachable_cells({})
	if baseline.is_empty():
		return source_chunks
	var keep: Array = []
	for chunk in source_chunks:
		var candidate := keep.duplicate()
		candidate.append(chunk)
		var blocked := _blocked_cells_of(candidate)
		var reachable := _reachable_cells(blocked)
		if _keeps_regions_open(baseline, blocked, reachable):
			keep = candidate
	return keep

func _blocked_cells_of(source_chunks: Array) -> Dictionary:
	var blocked: Dictionary = {}
	for chunk in source_chunks:
		if chunk is MapChunk:
			for cell in chunk.cells:
				blocked[cell] = true
	return blocked

func _reachable_cells(blocked: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var all_cells := MapChunks.get_all_cells()
	if all_cells.is_empty():
		return out
	var tree := get_tree()
	if tree == null:
		return out
	var player := tree.get_first_node_in_group("Player")
	if player == null or not (player is Node2D):
		return out
	var index: Dictionary = {}
	for i in all_cells.size():
		index[all_cells[i]] = i
	var start := MapChunks.world_to_cell((player as Node2D).global_position)
	if not index.has(start) or blocked.has(start):
		return out
	var queue: Array[Vector2i] = [start]
	out[start] = true
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for offset in NEIGHBOR_OFFSETS:
			var next: Vector2i = cur + offset
			if out.has(next) or blocked.has(next) or not index.has(next):
				continue
			out[next] = true
			queue.append(next)
	return out

func _keeps_regions_open(baseline: Dictionary, blocked: Dictionary, reachable: Dictionary) -> bool:
	for cell in baseline:
		if blocked.has(cell):
			continue
		if not reachable.has(cell):
			return false
	return true
