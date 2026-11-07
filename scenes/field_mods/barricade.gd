class_name BarricadeEffect
extends TerrainFieldEffect

## 壁垒：读取整图模板（Core 必放 + Optional 随机保留；Core/Optional 内可用随机贴图），
## 做减法避让与连通性保证。模板由 scenes/field_mods/barricade_template_editor.tscn 生成；
## 无模板时回退到 2×2 分块。

signal walls_built(cells: PackedVector2Array, variants: PackedByteArray)

const Layout = preload("res://scenes/field_mods/barricade_layout.gd")

const DEFAULT_TEMPLATE_DIR := "res://scenes/field_mods/barricade_templates"
const RANDOM_SOURCE_ID := 1
## 模板 Core/Optional 里 source 1 的格子 = 随机贴图；运行时才选 0..3 变体。
const RANDOM_VARIANT_MARKER := -1
const INVALID_CELL := Vector2i(2147483647, 2147483647)

enum ConnectivityScope { RANDOM_ONLY, ALL, OFF }

@export_group("Walls")
## 墙体 TileSet；必须含 bullet_wall(2) | wall(256) 物理层。
@export var wall_tile_set: TileSet
@export var wall_source_id: int = 0
## 回退 2×2 路径与模板随机贴图格共用的视觉变体权重；模板固定变体优先使用画的变体。
@export var variant_weights: Array[float] = [0.7, 0.1, 0.1, 0.1]

@export_group("Templates")
@export var template_dir: String = DEFAULT_TEMPLATE_DIR
## 固定测试某张模板（id 或文件名）；空 = 按权重随机。
@export var debug_template_id: String = ""
## 自由格低于该比例时放弃模板、回退 2×2，避免把地图封死。
## RANDOM_ONLY 下仅作警告，不再因此整图回退。
@export_range(0.0, 1.0, 0.05) var min_free_ratio: float = 0.15
## 模板画错出现封闭区时，沿墙格最短路径拆开；关闭则直接回退。
@export var repair_enclosed_regions: bool = true
## 0 = 随机；非 0 可复现整图模板的 Optional 保留结果。
@export var debug_seed: int = 0

@export_group("Connectivity")
## RANDOM_ONLY: Core 只诊断、不拆；只有 Optional（随机墙）会因堵路被回收。
## ALL: 旧行为（可拆 Core、可整图回退）。OFF: 不做连通检查。
@export var connectivity_scope: ConnectivityScope = ConnectivityScope.RANDOM_ONLY
## true = 建墙时不挖中心 240；等 Boss 登场再按实际位置清。
@export var defer_boss_avoidance: bool = true

@export_group("Visual")
## 建墙淡入（秒）；0 = 关闭。
@export var wall_fade_in: float = 0.35
## 清墙（Boss 登场 / 回合结束）淡出（秒）；0 = 关闭。
@export var wall_fade_out: float = 0.3

@export_group("Avoidance")
## 当前存活敌人半径。
@export var avoid_enemy_radius: float = 96.0
## 非 idle 召唤物半径。
@export var avoid_summoned_radius: float = 80.0
## 刷怪 portal 锚点半径（整图模板没有块级 portal 过滤）。
@export var avoid_portal_radius: float = 96.0

var _variants: Dictionary = {}
var _template_variants: Dictionary = {}
## 模板随机贴图格（source 1）保留到最终墙集的格子；这些格运行时每格随机取变体。
var _random_variant_cells: Dictionary = {}
var _templates: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
## 本次建墙要避让的 Boss 位置（已在场 / 当前遭遇计划）。
var _build_boss_positions: Array = []
var _boss_events_connected := false

func on_start() -> void:
	if wall_tile_set == null:
		push_warning("BarricadeEffect: wall_tile_set is missing")
		finish()
		return
	# 必须等 MapBounds 的墙射线稳定，否则新墙会被后续边界射线误当成地图外墙。
	if MapBounds.get_boundary_source() != &"walls":
		push_warning("BarricadeEffect: MapBounds is not ready (source=%s); skip this round" % MapBounds.get_boundary_source())
		finish()
		return
	if not MapChunks.ensure_ready():
		push_warning("BarricadeEffect: MapChunks is not ready; skip this round")
		finish()
		return
	var player := _find_player()
	var all_cells := MapChunks.get_all_cells()
	if player == null or all_cells.is_empty() or not all_cells.has(MapChunks.world_to_cell(player.global_position)):
		push_warning("BarricadeEffect: player/cell data is not ready; skip this round")
		finish()
		return
	if debug_seed != 0:
		_rng.seed = debug_seed
	else:
		_rng.randomize()
	_variants.clear()
	_template_variants.clear()
	_random_variant_cells.clear()
	_build_boss_positions = _collect_boss_positions()
	_parse_map_templates()
	super.on_start()
	# 建墙期间可能刚好有 Boss 加入/遭遇开始：建完再按实际位置清一次，随后接管后续事件。
	_clear_boss_positions(_collect_boss_positions())
	_connect_boss_events()
	EnemyNavField.complex_path_enabled = true

# ---------------- 模板解析 ----------------

func _parse_map_templates() -> void:
	_templates.clear()
	var all_cells := MapChunks.get_all_cells()
	if all_cells.is_empty():
		return
	var all_set := _cell_set(all_cells)
	for path in _template_files():
		var packed = load(path)
		if not (packed is PackedScene):
			push_warning("BarricadeEffect: template is not a PackedScene: %s" % path)
			continue
		var instance = (packed as PackedScene).instantiate()
		if instance == null:
			push_warning("BarricadeEffect: failed to instantiate template: %s" % path)
			continue
		var id := str(instance.get("id")) if instance.get("id") != null else ""
		if id == "":
			id = path.get_file().get_basename()
		var weight := float(instance.get("weight")) if instance.get("weight") != null else 1.0
		var keep_chance := float(instance.get("optional_keep_chance")) if instance.get("optional_keep_chance") != null else 0.5
		var layers := _read_template_layers(instance, all_set)
		if layers.is_empty():
			push_warning("BarricadeEffect: template '%s' has no readable Core layer" % path)
			continue
		var core: Dictionary = layers.get("core", {})
		if core.is_empty():
			push_warning("BarricadeEffect: template '%s' has an empty Core layer" % path)
			continue
		_templates.append({
			"id": id,
			"path": path,
			"weight": maxf(0.001, weight),
			"optional_keep_chance": clampf(keep_chance, 0.0, 1.0),
			"core": core,
			"optional": layers.get("optional", {}),
			"random": layers.get("random", {}),
		})
	if _templates.is_empty():
		push_warning("BarricadeEffect: no usable templates in '%s'; fallback to 2×2 chunks" % template_dir)

func _read_template_layers(instance: Node, all_set: Dictionary) -> Dictionary:
	var core := instance.get_node_or_null("Core")
	if not (core is TileMapLayer):
		instance.free()
		return {}
	if (core as TileMapLayer).get_used_cells().is_empty():
		# 防御：个别情况下离树 TileMapLayer 读不到 tile 数据，隐藏挂到场景树再读。
		var holder := Node2D.new()
		holder.visible = false
		add_child(holder)
		holder.add_child(instance)
		var data := _layers_to_data(instance.get_node_or_null("Core"), instance.get_node_or_null("Optional"), instance.get_node_or_null("Random"), all_set)
		holder.queue_free()
		return data
	var data := _layers_to_data(core, instance.get_node_or_null("Optional"), instance.get_node_or_null("Random"), all_set)
	instance.free()
	return data

func _layers_to_data(core, optional, random, all_set: Dictionary) -> Dictionary:
	var core_cells: Dictionary = {}
	if core is TileMapLayer:
		core_cells = _read_layer_cells(core as TileMapLayer, all_set)
	var optional_cells: Dictionary = {}
	if optional is TileMapLayer:
		optional_cells = _read_layer_cells(optional as TileMapLayer, all_set)
	var random_cells: Dictionary = {}
	if random is TileMapLayer:
		random_cells = _read_layer_cells(random as TileMapLayer, all_set)
	return {"core": core_cells, "optional": optional_cells, "random": random_cells}

func _read_layer_cells(layer: TileMapLayer, all_set: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for cell in layer.get_used_cells():
		if not (cell is Vector2i):
			continue
		if not all_set.has(cell):
			continue
		if layer.get_cell_source_id(cell) == RANDOM_SOURCE_ID:
			out[cell] = RANDOM_VARIANT_MARKER
			continue
		var atlas := layer.get_cell_atlas_coords(cell)
		out[cell] = clampi(atlas.x, 0, 3)
	return out

func _template_files() -> Array[String]:
	var out: Array[String] = []
	if DirAccess.dir_exists_absolute(template_dir):
		for file in DirAccess.get_files_at(template_dir):
			if file.ends_with(".tscn") and not file.begins_with("_"):
				out.append(template_dir.path_join(file))
	if out.is_empty():
		for file in ResourceLoader.list_directory(template_dir):
			if file.ends_with(".tscn") and not file.begins_with("_"):
				out.append(template_dir.path_join(file))
	out.sort()
	return out

# ---------------- 整图生成 ----------------

func _pick_terrain_chunks() -> Array[MapChunk]:
	if _templates.is_empty():
		return super._pick_terrain_chunks()
	var all_cells := MapChunks.get_all_cells()
	if all_cells.is_empty():
		return []
	var all_set := _cell_set(all_cells)
	var player := _find_player()
	var data := _pick_template()
	if data.is_empty():
		return super._pick_terrain_chunks()
	_random_variant_cells.clear()
	var template_id := str(data.get("id", ""))

	# ---- 分层：Core 必放 / Optional 按概率保留 ----
	var core: Dictionary = data.get("core", {})
	var core_set: Dictionary = {}
	var core_variants: Dictionary = {}
	var core_random: Dictionary = {}
	var core_outside := 0
	for cell in core.keys():
		if not (cell is Vector2i):
			continue
		if not all_set.has(cell):
			core_outside += 1
			continue
		core_set[cell] = true
		var core_variant := int(core[cell])
		if core_variant == RANDOM_VARIANT_MARKER:
			core_random[cell] = true
		else:
			core_variants[cell] = core_variant
	# 兼容上一版独立 Random 层：按 Core 类必放 + 随机贴图处理；新模板不再有该层。
	var legacy_random: Dictionary = data.get("random", {})
	for cell in legacy_random.keys():
		if all_set.has(cell) and not core_set.has(cell):
			core_set[cell] = true
			core_random[cell] = true
	var optional: Dictionary = data.get("optional", {})
	var keep_chance := float(data.get("optional_keep_chance", 0.5))
	var optional_set: Dictionary = {}
	var optional_variants: Dictionary = {}
	var optional_random: Dictionary = {}
	var optional_outside := 0
	for cell in optional.keys():
		if not (cell is Vector2i):
			continue
		if not all_set.has(cell):
			optional_outside += 1
			continue
		if core_set.has(cell):
			continue
		if _rng.randf() >= keep_chance:
			continue
		optional_set[cell] = true
		var optional_variant := int(optional[cell])
		if optional_variant == RANDOM_VARIANT_MARKER:
			optional_random[cell] = true
		else:
			optional_variants[cell] = optional_variant
	if core_outside > 0 or optional_outside > 0:
		push_warning("BarricadeEffect: template '%s' has %d core / %d optional cell(s) outside walkable area; skipped" % [
			template_id, core_outside, optional_outside,
		])

	# ---- 避让减法（Boss 中心可延后到 Boss 出场） ----
	var core_before := core_set.size()
	var optional_before := optional_set.size()
	var carve_ctx := _build_carve_ctx(player, all_cells)
	var both := _union_cells(core_set, optional_set)
	var world_of := Callable(MapChunks, "get_cell_world")
	var carve := Layout.carve_out(both, world_of, carve_ctx)
	var carve_removed: Dictionary = carve.get("removed", {})
	for cell in carve_removed.keys():
		core_set.erase(cell)
		core_variants.erase(cell)
		core_random.erase(cell)
		optional_set.erase(cell)
		optional_variants.erase(cell)
		optional_random.erase(cell)
	var carve_counts: Dictionary = carve.get("counts", {})
	if OS.is_debug_build():
		print("[Barricade] template '%s': core %d -> %d, optional %d -> %d, carve(player=%d center=%d boss=%d portal=%d enemy=%d summon=%d reserved=%d), boss_deferred=%s" % [
			template_id,
			core_before, core_set.size(),
			optional_before, optional_set.size(),
			int(carve_counts.get("player", 0)),
			int(carve_counts.get("center", 0)),
			int(carve_counts.get("boss", 0)),
			int(carve_counts.get("portal", 0)),
			int(carve_counts.get("enemy", 0)),
			int(carve_counts.get("summoned", 0)),
			int(carve_counts.get("reserved", 0)),
			str(defer_boss_avoidance),
		])

	# ---- 连通：只看可行走格 4 邻接；Core 只作基线，Optional（随机墙）才回收 ----
	var seed := MapChunks.world_to_cell(player.global_position) if player != null else INVALID_CELL
	if not all_set.has(seed):
		var center_node := get_tree().get_first_node_in_group("CenterPosition")
		if center_node is Node2D:
			seed = MapChunks.world_to_cell((center_node as Node2D).global_position)
	if not all_set.has(seed) and not all_cells.is_empty():
		seed = all_cells[0]
		push_warning("BarricadeEffect: player/center cell is not walkable; using first walkable cell %s" % str(seed))
	var final_wall: Dictionary = {}
	var final_variants: Dictionary = {}
	var final_random: Dictionary = {}
	if connectivity_scope == ConnectivityScope.ALL:
		final_wall = _union_cells(core_set, optional_set)
		final_variants = _merge_values(core_variants, optional_variants)
		final_random = _union_cells(core_random, optional_random)
		if not _ensure_connectivity(final_wall, final_variants, all_set, player, data):
			_template_variants.clear()
			_random_variant_cells.clear()
			return super._pick_terrain_chunks()
	elif connectivity_scope == ConnectivityScope.RANDOM_ONLY:
		var random_result := Layout.repair_optional_connectivity(core_set, optional_set, all_set, seed)
		var optional_removed: Array = random_result.get("optional_removed", [])
		for cell in optional_removed:
			optional_set.erase(cell)
			optional_variants.erase(cell)
			optional_random.erase(cell)
		final_wall = _union_cells(core_set, optional_set)
		final_variants = _merge_values(core_variants, optional_variants)
		final_random = _union_cells(core_random, optional_random)
		var core_unreachable: Dictionary = random_result.get("core_unreachable", {})
		var missing_after: Dictionary = random_result.get("missing_after", {})
		if OS.is_debug_build():
			print("[Barricade] template '%s': core_unreachable=%d (info), optional_removed=%d, dropped_all_optional=%s, missing_after=%d" % [
				template_id,
				core_unreachable.size(),
				optional_removed.size(),
				str(random_result.get("dropped_all_optional", false)),
				missing_after.size(),
			])
		if not bool(random_result.get("ok", true)):
			push_warning("BarricadeEffect: template '%s' connectivity repair failed (seed/core); core kept" % template_id)
		if not missing_after.is_empty():
			push_warning("BarricadeEffect: template '%s' still leaves %d required walkable cell(s) unreachable (core kept)" % [
				template_id, missing_after.size(),
			])
	else:
		final_wall = _union_cells(core_set, optional_set)
		final_variants = _merge_values(core_variants, optional_variants)
		final_random = _union_cells(core_random, optional_random)
	if final_wall.is_empty():
		push_warning("BarricadeEffect: template '%s' has no walls after avoidance; fallback" % template_id)
		_template_variants.clear()
		_random_variant_cells.clear()
		return super._pick_terrain_chunks()
	var free_count := all_cells.size() - final_wall.size()
	if free_count < int(floor(float(all_cells.size()) * min_free_ratio)):
		if connectivity_scope == ConnectivityScope.RANDOM_ONLY:
			push_warning("BarricadeEffect: template '%s' leaves only %d free cells (RANDOM_ONLY: kept)" % [template_id, free_count])
		else:
			push_warning("BarricadeEffect: template '%s' leaves only %d free cells; fallback" % [template_id, free_count])
			_template_variants.clear()
			_random_variant_cells.clear()
			return super._pick_terrain_chunks()
	var cells: Array[Vector2i] = []
	for cell in final_wall.keys():
		if cell is Vector2i:
			cells.append(cell)
	if cells.is_empty():
		_template_variants.clear()
		_random_variant_cells.clear()
		return super._pick_terrain_chunks()
	_template_variants = final_variants
	# 只保留最终仍在墙集里的 Random 格；被 carve-out / 连通性拆掉的格不再随机。
	for cell in final_random.keys():
		if final_wall.has(cell):
			_random_variant_cells[cell] = true
	return [_make_chunk(cells)]


func _union_cells(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for cell in a.keys():
		out[cell] = true
	for cell in b.keys():
		out[cell] = true
	return out


func _merge_values(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = a.duplicate()
	for cell in b.keys():
		out[cell] = b[cell]
	return out


func _build_carve_ctx(player: Node2D, all_cells: Array) -> Dictionary:
	var reserved := _cell_set(MapChunks.get_reserved_cells())
	var portal_cells: Dictionary = {}
	for cell in all_cells:
		if MapChunks.is_portal_cell(cell):
			portal_cells[cell] = true
	var portal_anchors: Array = []
	for side in 4:
		if MapChunks.is_side_anchor_valid(side):
			portal_anchors.append(MapChunks.get_side_anchor(side))
	var enemy_positions: Array = []
	for enemy in PoolManager.get_active_enemies():
		if enemy != null and is_instance_valid(enemy) and enemy is Node2D:
			enemy_positions.append((enemy as Node2D).global_position)
	var summoned_positions: Array = []
	for summoned in get_tree().get_nodes_in_group("Summoned"):
		if summoned == null or not is_instance_valid(summoned) or not (summoned is Node2D):
			continue
		var idle = summoned.get("is_idle")
		if idle != null and int(idle) == 1:
			continue
		summoned_positions.append((summoned as Node2D).global_position)
	var player_position := player.global_position if player != null else Vector2.ZERO
	var player_cell := MapChunks.world_to_cell(player_position) if player != null else INVALID_CELL
	var center_node := get_tree().get_first_node_in_group("CenterPosition")
	var center_position := (center_node as Node2D).global_position if center_node is Node2D else Vector2.ZERO
	return {
		"player_position": player_position,
		"player_cell": player_cell,
		"has_player": player != null,
		"avoid_player_radius": avoid_player_start_radius,
		"center_position": center_position,
		"has_center": center_node is Node2D,
		"avoid_center_radius": avoid_center_radius,
		"defer_boss_avoidance": defer_boss_avoidance,
		"portal_cells": portal_cells,
		"portal_anchors": portal_anchors,
		"avoid_portal_radius": avoid_portal_radius,
		"enemy_positions": enemy_positions,
		"avoid_enemy_radius": avoid_enemy_radius,
		"summoned_positions": summoned_positions,
		"avoid_summon_radius": avoid_summoned_radius,
		"reserved_cells": reserved,
		"boss_positions": _build_boss_positions,
	}

func _pick_template() -> Dictionary:
	if _templates.is_empty():
		return {}
	if debug_template_id != "":
		for data in _templates:
			var data_id := str(data.get("id", ""))
			var data_path := str(data.get("path", ""))
			var data_file := data_path.get_file().get_basename() if data_path != "" else ""
			if data_id == debug_template_id or data_file == debug_template_id:
				return data
		push_warning("BarricadeEffect: debug_template_id '%s' not found; fallback to weighted pick" % debug_template_id)
	var total := 0.0
	for data in _templates:
		total += maxf(0.0, float(data.get("weight", 1.0)))
	if total <= 0.0:
		return _templates[_rng.randi_range(0, _templates.size() - 1)]
	var roll := _rng.randf() * total
	for data in _templates:
		roll -= maxf(0.0, float(data.get("weight", 1.0)))
		if roll <= 0.0:
			return data
	return _templates[_templates.size() - 1]

func _ensure_connectivity(wall_set: Dictionary, wall_variants: Dictionary, all_set: Dictionary, player: Node2D, data: Dictionary) -> bool:
	var free: Dictionary = {}
	for cell in all_set.keys():
		if not wall_set.has(cell):
			free[cell] = true
	if free.is_empty():
		return false
	var seed := MapChunks.world_to_cell(player.global_position) if player != null else INVALID_CELL
	if not free.has(seed):
		var center_node := get_tree().get_first_node_in_group("CenterPosition")
		if center_node is Node2D:
			seed = MapChunks.world_to_cell((center_node as Node2D).global_position)
	if not free.has(seed):
		seed = free.keys()[0]
	var reachable := _bfs_reachable(seed, free)
	if reachable.size() == free.size():
		return true
	if not repair_enclosed_regions:
		push_warning("BarricadeEffect: template '%s' encloses %d free cell(s); repair disabled" % [str(data.get("id", "")), free.size() - reachable.size()])
		return false
	var removed: Array[Vector2i] = []
	var guard := wall_set.size() + 8
	while reachable.size() < free.size() and guard > 0:
		guard -= 1
		var path := _find_wall_bridge(wall_set, reachable, free)
		if path.is_empty():
			break
		for cell in path:
			if wall_set.has(cell):
				wall_set.erase(cell)
				wall_variants.erase(cell)
				free[cell] = true
				removed.append(cell)
		reachable = _bfs_reachable(seed, free)
	if not removed.is_empty():
		push_warning("BarricadeEffect: template '%s' had enclosed region(s); removed %d wall cell(s): %s" % [
			str(data.get("id", "")),
			removed.size(),
			str(removed),
		])
	return reachable.size() == free.size()


func _bfs_reachable(seed: Vector2i, free: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if not free.has(seed):
		return out
	var queue: Array[Vector2i] = [seed]
	out[seed] = true
	var head := 0
	while head < queue.size():
		var current := queue[head]
		head += 1
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = current + offset
			if free.has(next) and not out.has(next):
				out[next] = true
				queue.append(next)
	return out

func _find_wall_bridge(wall_set: Dictionary, reachable: Dictionary, free: Dictionary) -> Array[Vector2i]:
	var starts: Array[Vector2i] = []
	var goals: Dictionary = {}
	for cell in wall_set.keys():
		if not (cell is Vector2i):
			continue
		var start := false
		var goal := false
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
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
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
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

func _make_chunk(cells: Array[Vector2i]) -> MapChunk:
	var chunk := MapChunk.new()
	chunk.cells = cells
	chunk.size = Vector2i.ONE
	chunk.coords = Vector2i.ZERO
	var center := Vector2.ZERO
	for cell in cells:
		center += MapChunks.get_cell_world(cell)
	if not cells.is_empty():
		center /= float(cells.size())
	chunk.world_center = center
	chunk.walkable_ratio = 1.0
	chunk.portal_cell_count = 0
	chunk.spawnable_cell_count = 0
	return chunk

# ---------------- 回退 2×2 用 ----------------

# 基类已经检查玩家半径 / 中心 / portal / 预留格；这里补敌人与召唤物的硬避让。
func _allow_chunk(chunk: MapChunk, player: Node2D) -> bool:
	if not super._allow_chunk(chunk, player):
		return false
	if chunk == null or chunk.cells.is_empty():
		return false
	var blocked_cells: Dictionary = {}
	if player != null:
		blocked_cells[MapChunks.world_to_cell(player.global_position)] = true
	var enemy_positions: Array[Vector2] = []
	for enemy in PoolManager.get_active_enemies():
		if enemy == null or not is_instance_valid(enemy) or not (enemy is Node2D):
			continue
		var enemy_pos: Vector2 = (enemy as Node2D).global_position
		enemy_positions.append(enemy_pos)
		blocked_cells[MapChunks.world_to_cell(enemy_pos)] = true
	var summoned_positions: Array[Vector2] = []
	for summoned in get_tree().get_nodes_in_group("Summoned"):
		if summoned == null or not is_instance_valid(summoned) or not (summoned is Node2D):
			continue
		var idle = summoned.get("is_idle")
		if idle != null and int(idle) == 1:
			continue
		var summoned_pos: Vector2 = (summoned as Node2D).global_position
		summoned_positions.append(summoned_pos)
		blocked_cells[MapChunks.world_to_cell(summoned_pos)] = true
	for cell in chunk.cells:
		if blocked_cells.has(cell):
			return false
		var world := MapChunks.get_cell_world(cell)
		for enemy_pos in enemy_positions:
			if world.distance_to(enemy_pos) < avoid_enemy_radius:
				return false
		for summoned_pos in summoned_positions:
			if world.distance_to(summoned_pos) < avoid_summoned_radius:
				return false
	return true

# ---------------- 墙体层 ----------------

func _build_overlay() -> void:
	if wall_tile_set == null:
		return
	_variants.clear()
	# 场景里已挂好 ObstacleWall（BulletWall 组 + y_sort），运行时只填 cells；
	# 找不到时保留防御性创建，避免旧场景/复用时无墙体。
	_overlay = get_node_or_null("ObstacleWall") as TileMapLayer
	if _overlay == null:
		_overlay = TileMapLayer.new()
		_overlay.name = "ObstacleWall"
		add_child(_overlay)
	_overlay.clear()
	_overlay.tile_set = wall_tile_set
	_overlay.y_sort_enabled = true
	_overlay.y_sort_origin = -3
	_overlay.z_index = 0
	if not _overlay.is_in_group("BulletWall"):
		_overlay.add_to_group("BulletWall")
	# EnemyNavField 直接扫描 NavObstacle TileMapLayer 生成阻挡集（不再 add_block）。
	if not _overlay.is_in_group("NavObstacle"):
		_overlay.add_to_group("NavObstacle")
	for cell in _cells.keys():
		if not (cell is Vector2i):
			continue
		var variant: int
		if _random_variant_cells.has(cell):
			variant = _pick_variant()
		elif _template_variants.has(cell):
			variant = clampi(int(_template_variants[cell]), 0, 3)
		else:
			variant = _pick_variant()
		_variants[cell] = variant
		_overlay.set_cell(cell, wall_source_id, Vector2i(variant, 0))
	_start_wall_fade_in()
	_emit_walls_built()

func _start_wall_fade_in() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if wall_fade_in <= 0.0:
		_overlay.modulate = Color.WHITE
		return
	_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tween := create_tween()
	tween.tween_property(_overlay, "modulate:a", 1.0, wall_fade_in).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _pick_variant() -> int:
	var total := 0.0
	for weight in variant_weights:
		total += maxf(0.0, float(weight))
	if total <= 0.0:
		return 0
	var roll := _rng.randf() * total
	for i in variant_weights.size():
		roll -= maxf(0.0, float(variant_weights[i]))
		if roll <= 0.0:
			return clampi(i, 0, 3)
	return 0

func _emit_walls_built() -> void:
	var data := get_wall_data()
	walls_built.emit(data["cells"], data["variants"])

## 返回当前墙体快照：host 用于联机下发，避免客机重掷模板/随机变体。
func get_wall_data() -> Dictionary:
	var cells := PackedVector2Array()
	var variants := PackedByteArray()
	for cell in _cells.keys():
		if not (cell is Vector2i):
			continue
		cells.append(Vector2(cell.x, cell.y))
		variants.append(clampi(int(_variants.get(cell, 0)), 0, 3))
	return {"cells": cells, "variants": variants}

## 联机客机镜像：按 host 下发的墙格/变体直接重建，不跑模板、随机、避让或连通性。
func apply_network_walls(cells: PackedVector2Array, variants: PackedByteArray) -> void:
	if wall_tile_set == null:
		push_warning("BarricadeEffect: wall_tile_set is missing (network mirror)")
		return
	_cells.clear()
	_variants.clear()
	_template_variants.clear()
	_random_variant_cells.clear()
	for i in cells.size():
		var cell := Vector2i(int(cells[i].x), int(cells[i].y))
		_cells[cell] = true
		_variants[cell] = clampi(int(variants[i]) if i < variants.size() else 0, 0, 3)
	# 镜像没有走 start()/on_start()，但 stop()/on_stop() 需要 active=true 才会清理墙体层。
	_template_variants = _variants.duplicate()
	active = true
	_on_start_done = true
	_build_overlay()
	# 客机镜像没有走 TerrainFieldEffect.on_start 的 invalidate，必须在这里刷新 NavObstacle 拓扑，
	# 否则 MapBounds/医疗包安全查询会继续使用旧阻挡集。
	EnemyNavField.invalidate()

# ---------------- Boss 延后避让 / 淡出 ----------------

func _collect_boss_positions() -> Array:
	var out: Array = []
	var tree := get_tree()
	if tree == null:
		return out
	for boss in tree.get_nodes_in_group("BOSS"):
		if boss is Node2D and is_instance_valid(boss) and not boss.is_queued_for_deletion():
			out.append((boss as Node2D).global_position)
	var controller := tree.get_first_node_in_group("BossRoundController")
	if controller != null and controller.has_method("get_current_plan"):
		var plan: Dictionary = controller.get_current_plan()
		out.append_array(_entry_boss_positions(plan.get("entry")))
	return out


## 与 BossRoundController._spawn_card 的出生位置逻辑对齐。
func _entry_boss_positions(entry) -> Array:
	var out: Array = []
	if entry == null or entry.encounter == null:
		return out
	var cards: Array = entry.encounter.bosses
	var center_node := get_tree().get_first_node_in_group("CenterPosition")
	var center := (center_node as Node2D).global_position if center_node is Node2D else Vector2.ZERO
	for i in cards.size():
		var card = cards[i]
		var pos := Vector2.ZERO
		if entry.encounter.positions.size() > i:
			pos = entry.encounter.positions[i]
		elif card != null and card.spawn_position != Vector2.ZERO:
			pos = card.spawn_position
		elif cards.size() > 1:
			pos = center + Vector2((float(i) - (float(cards.size()) - 1.0) * 0.5) * 180.0, 0.0)
		if pos == Vector2.ZERO:
			pos = center
		if pos != Vector2.ZERO:
			out.append(pos)
	return out


func _clear_boss_positions(positions: Array) -> void:
	if positions.is_empty() or _cells.is_empty() or _overlay == null:
		return
	for pos in positions:
		if pos is Vector2:
			_clear_walls_in_radius(pos, avoid_center_radius, "boss")


func _connect_boss_events() -> void:
	if _boss_events_connected or GameEvents == null:
		return
	_boss_events_connected = true
	if not GameEvents.boss_encounter_started.is_connected(_on_boss_encounter_started):
		GameEvents.boss_encounter_started.connect(_on_boss_encounter_started)
	if not GameEvents.boss_joined.is_connected(_on_boss_joined):
		GameEvents.boss_joined.connect(_on_boss_joined)


func _disconnect_boss_events() -> void:
	_boss_events_connected = false
	if GameEvents == null:
		return
	if GameEvents.boss_encounter_started.is_connected(_on_boss_encounter_started):
		GameEvents.boss_encounter_started.disconnect(_on_boss_encounter_started)
	if GameEvents.boss_joined.is_connected(_on_boss_joined):
		GameEvents.boss_joined.disconnect(_on_boss_joined)


func _on_boss_encounter_started(entry, _plan: Dictionary) -> void:
	if _cells.is_empty() or _overlay == null:
		return
	_clear_boss_positions(_entry_boss_positions(entry))


func _on_boss_joined(boss, _entry) -> void:
	if _cells.is_empty() or _overlay == null:
		return
	if boss is Node2D and is_instance_valid(boss):
		_clear_walls_in_radius((boss as Node2D).global_position, avoid_center_radius, "boss")


func _clear_walls_in_radius(center: Vector2, radius: float, reason: String) -> int:
	if _cells.is_empty() or radius <= 0.0:
		return 0
	var removed_cells: Array = []
	var removed_variants: Dictionary = {}
	for cell in _cells.keys():
		if not (cell is Vector2i):
			continue
		if MapChunks.get_cell_world(cell).distance_to(center) < radius:
			removed_cells.append(cell)
			removed_variants[cell] = int(_variants.get(cell, 0))
	if removed_cells.is_empty():
		return 0
	var alpha := 1.0
	var z := 0
	var y_origin := -3
	if _overlay != null and is_instance_valid(_overlay):
		alpha = _overlay.modulate.a
		z = _overlay.z_index
		y_origin = _overlay.y_sort_origin
	for cell in removed_cells:
		_cells.erase(cell)
		_variants.erase(cell)
		_template_variants.erase(cell)
		_random_variant_cells.erase(cell)
		if _overlay != null and is_instance_valid(_overlay):
			_overlay.erase_cell(cell)
	_spawn_fade_ghost(removed_cells, removed_variants, alpha, z, y_origin, self)
	EnemyNavField.invalidate()
	_emit_walls_built()
	if OS.is_debug_build():
		print("[Barricade] boss clearance (%s) at %s r=%.0f removed %d wall cell(s)" % [
			reason, str(center), radius, removed_cells.size(),
		])
	return removed_cells.size()


## 被删/被清墙体的视觉残影：碰撞/导航已由主层立即更新，ghost 只负责淡出。
func _spawn_fade_ghost(cells: Array, variants: Dictionary, alpha: float, z: int, y_origin: int, parent: Node) -> void:
	if wall_tile_set == null or cells.is_empty() or wall_fade_out <= 0.0:
		return
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var ghost := TileMapLayer.new()
	ghost.name = "BarricadeFadeGhost"
	ghost.tile_set = wall_tile_set
	ghost.collision_enabled = false
	ghost.y_sort_enabled = true
	ghost.y_sort_origin = y_origin
	ghost.z_index = z
	ghost.modulate = Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0))
	for cell in cells:
		if not (cell is Vector2i):
			continue
		ghost.set_cell(cell, wall_source_id, Vector2i(int(variants.get(cell, 0)), 0))
	parent.add_child(ghost)
	var tween := ghost.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(ghost, "modulate:a", 0.0, wall_fade_out).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(ghost.queue_free)


func on_stop() -> void:
	var fade_cells := _cells.duplicate()
	var fade_variants := _variants.duplicate()
	var fade_alpha := 1.0
	var fade_z := 0
	var fade_y := -3
	var parent := get_parent()
	if _overlay != null and is_instance_valid(_overlay):
		fade_alpha = _overlay.modulate.a
		fade_z = _overlay.z_index
		fade_y = _overlay.y_sort_origin
		_overlay.visible = false
	super.on_stop()
	_disconnect_boss_events()
	EnemyNavField.complex_path_enabled = false
	# 效果节点随后会被 FieldModManager queue_free；残影必须挂到父节点才能活到淡出结束。
	_spawn_fade_ghost(fade_cells.keys(), fade_variants, fade_alpha, fade_z, fade_y, parent)


func _exit_tree() -> void:
	_disconnect_boss_events()
	super._exit_tree()


func on_terrain_stop() -> void:
	_variants.clear()
	_template_variants.clear()
	_random_variant_cells.clear()
	_templates.clear()

func _cell_set(cells: Array) -> Dictionary:
	var out: Dictionary = {}
	for cell in cells:
		if cell is Vector2i:
			out[cell] = true
	return out
