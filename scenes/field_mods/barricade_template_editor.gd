extends Node2D

## 壁垒整图模板编辑工具。
## 运行方式：打开本场景按 F6，或用 project_run(mode="custom", scene=...)。
## 红边界 = 当前主地图的可走菱形；Core = 必放墙，Optional = 每回合按概率保留的墙。
## 随机只是外墙贴图选项：Core/Optional 都可以用“随机贴图”，用第一墙体改绿色表示。

const TEMPLATE_SCRIPT := "res://scenes/field_mods/obstacle_map_template.gd"
const TEMPLATE_DIR := "res://scenes/field_mods/barricade_templates"
const MAIN_SCENE := "res://scenes/main/main.tscn"
const BARRICADE_SCENE := "res://scenes/field_mods/barricade.tscn"
const ZONE_OVERLAY_SCRIPT := preload("res://scenes/field_mods/barricade_zone_overlay.gd")
const Layout = preload("res://scenes/field_mods/barricade_layout.gd")
const TILE_TEXTURE_PATH := "res://sprites/tile_map/tile_wall_1.png"
const RANDOM_TEXTURE_PATH := "res://sprites/tile_map/tile_wall_random.png"
const MAP_CENTER := Vector2(704.0, 448.0)
const MAP_HALF := Vector2(864.0, 432.0)
const UI_PANEL_WIDTH := 190.0
const SOURCE_ID := 0
const RANDOM_SOURCE_ID := 1
const RANDOM_VARIANT := 4
const GRID_RADIUS := 60
const TILE_HALF := Vector2(32.0, 16.0)

enum PaintMode { CORE, OPTIONAL }

@onready var camera: Camera2D = $Camera2D
@onready var world: Node2D = $World
@onready var core_edit: TileMapLayer = $World/CoreEdit
@onready var optional_edit: TileMapLayer = $World/OptionalEdit
@onready var boundary: Line2D = $World/Boundary
@onready var cursor: Line2D = $World/Cursor
@onready var ui_layer: CanvasLayer = $UI

var _panel: PanelContainer
var _name_edit: LineEdit
var _weight_spin: SpinBox
var _keep_slider: HSlider
var _keep_label: Label
var _counts_label: Label
var _runtime_label: Label
var _status_label: Label
var _template_list: ItemList
var _core_button: Button
var _optional_button: Button
var _grid_toggle: CheckButton
var _zones_toggle: CheckButton
var _preview_toggle: CheckButton
var _save_dialog: ConfirmationDialog
var _delete_dialog: ConfirmationDialog
var _palette_buttons: Array[TextureButton] = []
var _palette_row: HBoxContainer
var _boundary_points := PackedVector2Array()
var _template_paths: Dictionary = {}
var _current_variant := 0
var _mode: int = PaintMode.CORE
var _show_grid := true
var _show_zones := true
var _preview_on := false
var _painting := false
var _paint_button := 0
var _panning := false
var _last_painted_cell := Vector2i(2147483647, 2147483647)
var _pending_save_path := ""
var _pending_delete_path := ""

# 实机参考（main.tscn / barricade.tscn）
var _refs_ready := false
var _center_position := MAP_CENTER
var _center_cell := Vector2i.ZERO
var _portal_anchors: Array = []
var _portal_cells: Dictionary = {}
var _spawnable_cells: Dictionary = {}
var _walkable_cells: Dictionary = {}
var _avoid_player_radius := 64.0
var _avoid_center_radius := 240.0
var _avoid_portal_radius := 96.0
var _defer_boss_avoidance := true
var _connectivity_scope := 0
var _carve_removed: Dictionary = {}
var _zone_overlay: Node2D
var _preview_layer: TileMapLayer
var _runtime_dirty := false
var _last_preview_ms := 0

func _ready() -> void:
	_setup_editor_y_sort()
	camera.offset = Vector2(UI_PANEL_WIDTH * 0.5, 0.0)
	_build_boundary()
	_build_ui()
	_load_runtime_refs()
	_build_walkable_cells()
	_build_preview_layer()
	_build_zone_overlay()
	_build_palette()
	_build_save_dialog()
	_build_delete_dialog()
	_refresh_template_list()
	_set_mode(PaintMode.CORE)
	_set_variant(0)
	if FileAccess.file_exists(TEMPLATE_DIR.path_join("default.tscn")):
		_load_path(TEMPLATE_DIR.path_join("default.tscn"))
	else:
		_new_template()
	_update_counts()
	_update_runtime_preview()
	queue_redraw()

## 编辑器预览也要按墙块视觉底边排序；只开战斗墙层不够，否则工具里前方墙不遮挡后方墙。
func _setup_editor_y_sort() -> void:
	world.y_sort_enabled = true
	for layer in [core_edit, optional_edit]:
		var map_layer := layer as TileMapLayer
		if map_layer == null:
			continue
		map_layer.y_sort_enabled = true
		map_layer.y_sort_origin = -3

func _process(_delta: float) -> void:
	_update_cursor()
	if _runtime_dirty and Time.get_ticks_msec() - _last_preview_ms >= 150:
		_runtime_dirty = false
		_last_preview_ms = Time.get_ticks_msec()
		_update_runtime_preview()

func _draw() -> void:
	if not _show_grid:
		return
	var center_cell := core_edit.local_to_map(core_edit.to_local(MAP_CENTER))
	var grid_color := Color(1.0, 1.0, 1.0, 0.055)
	for dx in range(-GRID_RADIUS, GRID_RADIUS + 1):
		for dy in range(-GRID_RADIUS, GRID_RADIUS + 1):
			var cell := center_cell + Vector2i(dx, dy)
			var center := core_edit.to_global(core_edit.map_to_local(cell))
			if not Geometry2D.is_point_in_polygon(center, _boundary_points):
				continue
			var pts := PackedVector2Array([
				center + Vector2(0.0, -TILE_HALF.y),
				center + Vector2(TILE_HALF.x, 0.0),
				center + Vector2(0.0, TILE_HALF.y),
				center + Vector2(-TILE_HALF.x, 0.0),
				center + Vector2(0.0, -TILE_HALF.y),
			])
			draw_polyline(pts, grid_color, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				var factor := 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
				var zoom_value := clampf(camera.zoom.x * factor, 0.15, 1.2)
				camera.zoom = Vector2(zoom_value, zoom_value)
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
			return
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_painting = mb.pressed
			_paint_button = mb.button_index
			_last_painted_cell = Vector2i(2147483647, 2147483647)
			if mb.pressed:
				_paint_at_hovered(mb.button_index == MOUSE_BUTTON_RIGHT)
			return
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			camera.position -= mm.relative / camera.zoom.x
		elif _painting:
			_paint_at_hovered(_paint_button == MOUSE_BUTTON_RIGHT)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode >= KEY_1 and key.keycode <= KEY_4:
				_set_variant(int(key.keycode - KEY_1))
			elif key.keycode == KEY_C:
				_set_mode(PaintMode.CORE)
			elif key.keycode == KEY_O:
				_set_mode(PaintMode.OPTIONAL)
			elif key.keycode == KEY_R:
				_set_variant(RANDOM_VARIANT)
			elif key.keycode == KEY_S and key.ctrl_pressed:
				_save_current()

func _build_boundary() -> void:
	_boundary_points = PackedVector2Array([
		MAP_CENTER + Vector2(0.0, -MAP_HALF.y),
		MAP_CENTER + Vector2(MAP_HALF.x, 0.0),
		MAP_CENTER + Vector2(0.0, MAP_HALF.y),
		MAP_CENTER + Vector2(-MAP_HALF.x, 0.0),
	])
	boundary.points = _boundary_points
	boundary.closed = true
	cursor.points = PackedVector2Array([
		Vector2(0.0, -TILE_HALF.y),
		Vector2(TILE_HALF.x, 0.0),
		Vector2(0.0, TILE_HALF.y),
		Vector2(-TILE_HALF.x, 0.0),
	])
	cursor.closed = true
	cursor.visible = false

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "EditorPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_right = UI_PANEL_WIDTH
	ui_layer.add_child(_panel)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 2)
	_panel.add_child(root_box)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(box)

	box.add_child(_make_label("壁垒模板编辑", 12))
	box.add_child(_make_label("名称", 10))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "my_template"
	_name_edit.add_theme_font_size_override("font_size", 10)
	_name_edit.custom_minimum_size = Vector2(0.0, 20.0)
	box.add_child(_name_edit)

	var weight_row := HBoxContainer.new()
	weight_row.add_child(_make_label("权重", 10))
	_weight_spin = SpinBox.new()
	_weight_spin.min_value = 0.1
	_weight_spin.max_value = 10.0
	_weight_spin.step = 0.1
	_weight_spin.value = 1.0
	_weight_spin.custom_minimum_size = Vector2(70.0, 20.0)
	_weight_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weight_spin.get_line_edit().add_theme_font_size_override("font_size", 10)
	weight_row.add_child(_weight_spin)
	box.add_child(weight_row)

	var keep_row := HBoxContainer.new()
	keep_row.add_child(_make_label("Optional", 10))
	_keep_slider = HSlider.new()
	_keep_slider.min_value = 0.0
	_keep_slider.max_value = 1.0
	_keep_slider.step = 0.05
	_keep_slider.value = 0.5
	_keep_slider.custom_minimum_size = Vector2(70.0, 20.0)
	_keep_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keep_slider.value_changed.connect(_on_keep_changed)
	keep_row.add_child(_keep_slider)
	_keep_label = _make_label("50%", 10)
	_keep_label.custom_minimum_size = Vector2(34.0, 0.0)
	keep_row.add_child(_keep_label)
	box.add_child(keep_row)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 2)
	_core_button = Button.new()
	_core_button.text = "Core"
	_core_button.tooltip_text = "必放；贴图可用变体 0~3 或随机"
	_core_button.toggle_mode = true
	_core_button.add_theme_font_size_override("font_size", 9)
	_core_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_core_button.pressed.connect(func() -> void: _set_mode(PaintMode.CORE))
	mode_row.add_child(_core_button)
	_optional_button = Button.new()
	_optional_button.text = "Optional"
	_optional_button.tooltip_text = "每回合按概率保留；贴图可用变体 0~3 或随机"
	_optional_button.toggle_mode = true
	_optional_button.add_theme_font_size_override("font_size", 9)
	_optional_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_optional_button.pressed.connect(func() -> void: _set_mode(PaintMode.OPTIONAL))
	mode_row.add_child(_optional_button)
	box.add_child(mode_row)

	box.add_child(_make_label("贴图（左键画 / 右键擦；绿=随机）", 9))
	_palette_row = HBoxContainer.new()
	_palette_row.add_theme_constant_override("separation", 4)
	box.add_child(_palette_row)

	_template_list = ItemList.new()
	_template_list.custom_minimum_size = Vector2(0.0, 60.0)
	_template_list.add_theme_font_size_override("font_size", 10)
	_template_list.item_activated.connect(func(_index: int) -> void: _load_selected())
	box.add_child(_template_list)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 1)
	var new_button := Button.new()
	new_button.text = "New"
	new_button.add_theme_font_size_override("font_size", 8)
	new_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_button.pressed.connect(_new_template)
	action_row.add_child(new_button)
	var save_button := Button.new()
	save_button.text = "Save"
	save_button.add_theme_font_size_override("font_size", 8)
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_save_current)
	action_row.add_child(save_button)
	var load_button := Button.new()
	load_button.text = "Load"
	load_button.add_theme_font_size_override("font_size", 8)
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_button.pressed.connect(_load_selected)
	action_row.add_child(load_button)
	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.add_theme_font_size_override("font_size", 8)
	refresh_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_button.pressed.connect(_refresh_template_list)
	action_row.add_child(refresh_button)
	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.tooltip_text = "删除列表中选中的模板"
	delete_button.add_theme_font_size_override("font_size", 8)
	delete_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_button.pressed.connect(_delete_selected)
	action_row.add_child(delete_button)
	box.add_child(action_row)

	_grid_toggle = CheckButton.new()
	_grid_toggle.text = "显示网格"
	_grid_toggle.button_pressed = true
	_grid_toggle.add_theme_font_size_override("font_size", 10)
	_grid_toggle.toggled.connect(func(pressed: bool) -> void:
		_show_grid = pressed
		queue_redraw()
	)
	box.add_child(_grid_toggle)

	_zones_toggle = CheckButton.new()
	_zones_toggle.text = "显示实机避让"
	_zones_toggle.button_pressed = true
	_zones_toggle.add_theme_font_size_override("font_size", 10)
	_zones_toggle.toggled.connect(func(pressed: bool) -> void:
		_show_zones = pressed
		if _zone_overlay != null and is_instance_valid(_zone_overlay):
			_zone_overlay.visible = pressed
	)
	box.add_child(_zones_toggle)

	_preview_toggle = CheckButton.new()
	_preview_toggle.text = "预览实机墙体"
	_preview_toggle.add_theme_font_size_override("font_size", 10)
	_preview_toggle.toggled.connect(func(pressed: bool) -> void:
		_set_preview(pressed)
	)
	box.add_child(_preview_toggle)

	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 2)
	root_box.add_child(footer)
	_counts_label = _make_label("Core 0 / Optional 0 / 随机贴图 0", 10)
	footer.add_child(_counts_label)
	_runtime_label = _make_label("实机参考加载中…", 9)
	_runtime_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_runtime_label.custom_minimum_size = Vector2(0.0, 92.0)
	footer.add_child(_runtime_label)
	_status_label = _make_label("", 10)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.custom_minimum_size = Vector2(0.0, 34.0)
	footer.add_child(_status_label)

func _build_palette() -> void:
	var palette_row := _palette_row
	var texture := load(TILE_TEXTURE_PATH) as Texture2D
	var random_texture := load(RANDOM_TEXTURE_PATH) as Texture2D
	for i in 4:
		var button := TextureButton.new()
		button.custom_minimum_size = Vector2(30.0, 30.0)
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.tooltip_text = "变体 %d" % i
		if texture != null:
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(float(i) * 64.0, 0.0, 64.0, 64.0)
			button.texture_normal = atlas
		button.pressed.connect(func() -> void: _set_variant(i))
		palette_row.add_child(button)
		_palette_buttons.append(button)
	var random_button := TextureButton.new()
	random_button.custom_minimum_size = Vector2(30.0, 30.0)
	random_button.ignore_texture_size = true
	random_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	random_button.tooltip_text = "随机贴图：Core 必放 / Optional 按概率保留，运行时随机取 0~3 变体"
	if random_texture != null:
		random_button.texture_normal = random_texture
	random_button.pressed.connect(func() -> void: _set_variant(RANDOM_VARIANT))
	palette_row.add_child(random_button)
	_palette_buttons.append(random_button)

func _build_save_dialog() -> void:
	_save_dialog = ConfirmationDialog.new()
	_save_dialog.title = "覆盖模板"
	_save_dialog.confirmed.connect(_on_save_confirmed)
	add_child(_save_dialog)

func _build_delete_dialog() -> void:
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "删除模板"
	_delete_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_dialog)

func _make_label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label

func _on_keep_changed(value: float) -> void:
	_keep_label.text = "%d%%" % roundi(value * 100.0)

func _set_mode(mode: int) -> void:
	_mode = clampi(mode, PaintMode.CORE, PaintMode.OPTIONAL)
	var core_on := _mode == PaintMode.CORE
	var optional_on := _mode == PaintMode.OPTIONAL
	core_edit.modulate = Color(1.25, 1.25, 1.25, 1.0) if core_on else Color(1.0, 1.0, 1.0, 0.55)
	optional_edit.modulate = Color(0.6, 0.9, 1.25, 1.0) if optional_on else Color(0.6, 0.8, 1.0, 0.55)
	if _core_button != null:
		_core_button.set_pressed_no_signal(core_on)
	if _optional_button != null:
		_optional_button.set_pressed_no_signal(optional_on)

func _set_variant(variant: int) -> void:
	_current_variant = clampi(variant, 0, RANDOM_VARIANT)
	for i in _palette_buttons.size():
		_palette_buttons[i].modulate = Color(1.0, 1.0, 0.35, 1.0) if i == _current_variant else Color.WHITE

func _paint_layer() -> TileMapLayer:
	return optional_edit if _mode == PaintMode.OPTIONAL else core_edit

func _erase_other_layers(cell: Vector2i, keep: TileMapLayer) -> void:
	for layer in [core_edit, optional_edit]:
		if layer != keep:
			(layer as TileMapLayer).erase_cell(cell)

func _hovered_cell() -> Vector2i:
	var layer := _paint_layer()
	return layer.local_to_map(layer.get_local_mouse_position())

func _inside_boundary(cell: Vector2i) -> bool:
	var layer := _paint_layer()
	var center := layer.to_global(layer.map_to_local(cell))
	return Geometry2D.is_point_in_polygon(center, _boundary_points)

func _update_cursor() -> void:
	if cursor == null:
		return
	if _preview_on:
		cursor.visible = false
		return
	if _panel != null and _panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
		cursor.visible = false
		return
	var cell := _hovered_cell()
	if not _inside_boundary(cell):
		cursor.visible = false
		return
	var layer := _paint_layer()
	cursor.position = layer.to_global(layer.map_to_local(cell))
	cursor.default_color = Color(0.35, 0.85, 1.0, 0.95) if _mode == PaintMode.OPTIONAL else Color(1.0, 0.35, 0.3, 0.95)
	cursor.visible = true

func _paint_at_hovered(erase: bool) -> void:
	if _preview_on:
		return
	var cell := _hovered_cell()
	if not _inside_boundary(cell):
		return
	if cell == _last_painted_cell:
		return
	_last_painted_cell = cell
	var layer := _paint_layer()
	if erase:
		layer.erase_cell(cell)
	else:
		if _current_variant == RANDOM_VARIANT:
			layer.set_cell(cell, RANDOM_SOURCE_ID, Vector2i(0, 0))
		else:
			layer.set_cell(cell, SOURCE_ID, Vector2i(_current_variant, 0))
		_erase_other_layers(cell, layer)
	_update_counts()

func _count_random_markers() -> int:
	var count := 0
	for layer in [core_edit, optional_edit]:
		var map_layer := layer as TileMapLayer
		for cell in map_layer.get_used_cells():
			if map_layer.get_cell_source_id(cell) == RANDOM_SOURCE_ID:
				count += 1
	return count

func _update_counts() -> void:
	if _counts_label == null:
		return
	_counts_label.text = "Core %d / Optional %d / 随机贴图 %d" % [
		core_edit.get_used_cells().size(),
		optional_edit.get_used_cells().size(),
		_count_random_markers(),
	]
	_runtime_dirty = true

func _update_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


# ---------------- 实机参考 / 预览 ----------------

func _load_runtime_refs() -> void:
	_refs_ready = false
	_center_position = MAP_CENTER
	_portal_anchors = [Vector2(704, 144), Vector2(1312, 448), Vector2(704, 752), Vector2(96, 448)]
	_portal_cells = {}
	_spawnable_cells = {}
	_avoid_player_radius = 64.0
	_avoid_center_radius = 240.0
	_avoid_portal_radius = 96.0
	_defer_boss_avoidance = true
	_connectivity_scope = 0
	var barricade_loaded := false
	var packed_barricade = load(BARRICADE_SCENE)
	if packed_barricade is PackedScene:
		var inst = (packed_barricade as PackedScene).instantiate()
		if inst != null:
			if inst.get("avoid_player_start_radius") != null:
				_avoid_player_radius = float(inst.get("avoid_player_start_radius"))
			if inst.get("avoid_center_radius") != null:
				_avoid_center_radius = float(inst.get("avoid_center_radius"))
			if inst.get("avoid_portal_radius") != null:
				_avoid_portal_radius = float(inst.get("avoid_portal_radius"))
			if inst.get("defer_boss_avoidance") != null:
				_defer_boss_avoidance = bool(inst.get("defer_boss_avoidance"))
			if inst.get("connectivity_scope") != null:
				_connectivity_scope = int(inst.get("connectivity_scope"))
			barricade_loaded = true
			inst.free()
	var main_loaded := false
	var packed_main = load(MAIN_SCENE)
	if packed_main is PackedScene:
		var main = (packed_main as PackedScene).instantiate()
		if main != null:
			var center := main.get_node_or_null("BattleRoom")
			if center is Node2D:
				_center_position = (center as Node2D).global_position
			var spawn_map := main.get_node_or_null("YSort/SpawnMap")
			if spawn_map != null:
				for cell in _used_cells(spawn_map):
					if cell is Vector2i:
						_spawnable_cells[cell] = true
			var anchors: Array = []
			for node_name in ["YSort/SpawnNorth", "YSort/SpawnEast", "YSort/SpawnSouth", "YSort/SpawnWest"]:
				var node := main.get_node_or_null(node_name)
				if node == null:
					continue
				var cells: Array = _used_cells(node)
				if cells.is_empty():
					continue
				var sum := Vector2.ZERO
				for cell in cells:
					if cell is Vector2i:
						_portal_cells[cell] = true
						sum += _node_cell_world(node, cell)
				anchors.append(sum / float(cells.size()))
			if anchors.size() == 4:
				_portal_anchors = anchors
			main_loaded = true
			main.free()
	_refs_ready = main_loaded and barricade_loaded
	if not _refs_ready and _runtime_label != null:
		_runtime_label.text = "未能读取 main.tscn / barricade.tscn；避让圈使用内置常量（近似）。"


func _node_cell_world(node: Node, cell: Vector2i) -> Vector2:
	if node is Node2D and node.has_method("map_to_local"):
		var local: Vector2 = node.call("map_to_local", cell)
		return (node as Node2D).to_global(local)
	return Vector2.ZERO


func _used_cells(node: Node) -> Array:
	if node is TileMap:
		return (node as TileMap).get_used_cells(0)
	if node is TileMapLayer:
		return (node as TileMapLayer).get_used_cells()
	return []


func _build_walkable_cells() -> void:
	_walkable_cells.clear()
	var inset: PackedVector2Array = _boundary_points
	var result := Geometry2D.offset_polygon(_boundary_points, -8.0, Geometry2D.JOIN_MITER)
	if result.size() > 0 and result[0].size() >= 3:
		inset = result[0]
	if inset.size() < 3:
		return
	var min_cell := Vector2i(2147483647, 2147483647)
	var max_cell := Vector2i(-2147483647, -2147483647)
	for p in _boundary_points:
		var cell := core_edit.local_to_map(core_edit.to_local(p))
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	for x in range(min_cell.x - 2, max_cell.x + 3):
		for y in range(min_cell.y - 2, max_cell.y + 3):
			var cell := Vector2i(x, y)
			if Geometry2D.is_point_in_polygon(_cell_world(cell), inset):
				_walkable_cells[cell] = true
	_center_cell = core_edit.local_to_map(core_edit.to_local(_center_position))


func _cell_world(cell: Vector2i) -> Vector2:
	return core_edit.to_global(core_edit.map_to_local(cell))


func _build_preview_layer() -> void:
	_preview_layer = TileMapLayer.new()
	_preview_layer.name = "PreviewEdit"
	_preview_layer.tile_set = core_edit.tile_set
	_preview_layer.collision_enabled = false
	_preview_layer.y_sort_enabled = true
	_preview_layer.y_sort_origin = -3
	_preview_layer.z_index = 1
	_preview_layer.modulate = Color(0.55, 1.0, 0.65, 0.55)
	_preview_layer.visible = false
	world.add_child(_preview_layer)


func _build_zone_overlay() -> void:
	_zone_overlay = Node2D.new()
	_zone_overlay.name = "RuntimeZones"
	_zone_overlay.set_script(ZONE_OVERLAY_SCRIPT)
	_zone_overlay.z_index = 3
	_zone_overlay.visible = _show_zones
	world.add_child(_zone_overlay)


func _set_preview(pressed: bool) -> void:
	_preview_on = pressed
	core_edit.visible = not pressed
	optional_edit.visible = not pressed
	if _preview_layer != null and is_instance_valid(_preview_layer):
		_preview_layer.visible = pressed
	_update_runtime_preview()
	_update_cursor()


func _collect_layer_cells(layer: TileMapLayer) -> Dictionary:
	var out: Dictionary = {}
	for cell in layer.get_used_cells():
		if not (cell is Vector2i):
			continue
		out[cell] = {
			"source": layer.get_cell_source_id(cell),
			"atlas": layer.get_cell_atlas_coords(cell),
		}
	return out


func _make_editor_carve_ctx() -> Dictionary:
	return {
		"player_position": _center_position,
		"player_cell": _center_cell,
		"has_player": true,
		"avoid_player_radius": _avoid_player_radius,
		"center_position": _center_position,
		"has_center": true,
		"avoid_center_radius": _avoid_center_radius,
		"defer_boss_avoidance": _defer_boss_avoidance,
		"portal_cells": _portal_cells,
		"portal_anchors": _portal_anchors,
		"avoid_portal_radius": _avoid_portal_radius,
		"enemy_positions": [],
		"avoid_enemy_radius": 0.0,
		"summoned_positions": [],
		"avoid_summon_radius": 0.0,
		"reserved_cells": {},
		"boss_positions": [],
	}


func _update_runtime_preview() -> void:
	if _runtime_label == null:
		return
	if _walkable_cells.is_empty():
		_runtime_label.text = "实机参考未就绪（main.tscn 读取失败或红边界为空）。"
		return
	var core_cells := _collect_layer_cells(core_edit)
	var optional_cells := _collect_layer_cells(optional_edit)
	var wall_keys: Dictionary = {}
	for cell in core_cells.keys():
		wall_keys[cell] = true
	for cell in optional_cells.keys():
		wall_keys[cell] = true
	var world_of := Callable(self, "_cell_world")
	var carve := Layout.carve_out(wall_keys, world_of, _make_editor_carve_ctx())
	_carve_removed = carve.get("removed", {})
	var core_after: Dictionary = {}
	for cell in core_cells.keys():
		if not _carve_removed.has(cell):
			core_after[cell] = true
	var optional_after: Dictionary = {}
	for cell in optional_cells.keys():
		if not _carve_removed.has(cell):
			optional_after[cell] = true
	var keep := _keep_slider.value if _keep_slider != null else 0.5
	var expected_optional := int(round(float(optional_after.size()) * keep))
	# 预览按 Optional 全保留（最坏情况）跑连通，运行时再按 keep 随机。
	var connectivity := Layout.repair_optional_connectivity(
		core_after, optional_after, _walkable_cells, _center_cell
	)
	var kept_optional: Dictionary = connectivity.get("kept_optional", {})
	var core_unreachable: Dictionary = connectivity.get("core_unreachable", {})
	var optional_removed: Array = connectivity.get("optional_removed", [])
	var dropped_all := bool(connectivity.get("dropped_all_optional", false))
	var final_wall: Dictionary = {}
	for cell in core_after.keys():
		final_wall[cell] = true
	for cell in kept_optional.keys():
		final_wall[cell] = true
	var boss_probe := final_wall.duplicate()
	var boss_removed: Array = []
	if _defer_boss_avoidance:
		boss_removed = Layout.clear_in_radius(boss_probe, world_of, _center_position, _avoid_center_radius)
	if _preview_layer != null and is_instance_valid(_preview_layer):
		_preview_layer.clear()
		for cell in final_wall.keys():
			var info: Dictionary = core_cells.get(cell, optional_cells.get(cell, {}))
			if info.is_empty():
				continue
			var atlas: Vector2i = info.get("atlas", Vector2i.ZERO)
			_preview_layer.set_cell(cell, int(info.get("source", 0)), atlas)
	if _zone_overlay != null and is_instance_valid(_zone_overlay):
		var carve_points: Array = []
		for cell in _carve_removed.keys():
			carve_points.append(_cell_world(cell))
		var spawn_points: Array = []
		for cell in _spawnable_cells.keys():
			spawn_points.append(_cell_world(cell))
		var core_unreachable_points: Array = []
		for cell in core_unreachable.keys():
			core_unreachable_points.append(_cell_world(cell))
		_zone_overlay.call("set_data", {
			"center": _center_position,
			"player_radius": _avoid_player_radius,
			"portal_anchors": _portal_anchors,
			"portal_radius": _avoid_portal_radius,
			"boss_radius": _avoid_center_radius,
			"show_boss": _defer_boss_avoidance,
			"carve_points": carve_points,
			"core_unreachable_points": core_unreachable_points,
			"spawn_cells": spawn_points,
		})
	var counts: Dictionary = carve.get("counts", {})
	var scope_name := "RANDOM_ONLY" if _connectivity_scope == 0 else ("ALL" if _connectivity_scope == 1 else "OFF")
	var optional_note := ""
	if optional_cells.is_empty():
		optional_note = "（无 Optional）"
	elif keep <= 0.0:
		optional_note = "（keep=0，本轮不生成）"
	else:
		optional_note = "（全保留预演；实际按 keep 随机）"
	var optional_removed_display := optional_removed.size() if keep > 0.0 and not optional_cells.is_empty() else 0
	var dropped_note := "（本轮全丢）" if dropped_all and keep > 0.0 and not optional_cells.is_empty() else ""
	_runtime_label.text = "实机预计（玩家在中心）\nCore %d → %d ｜ Optional %d → 期望 %d%s\n建墙避让：player %d / portal %d\nBoss 登场再删约 %d ｜ scope=%s\n连通：Core 自身不可达 %d（信息，不处理）｜Optional 回收 %d%s" % [
		core_cells.size(), core_after.size(),
		optional_cells.size(), expected_optional, optional_note,
		int(counts.get("player", 0)), int(counts.get("portal", 0)),
		boss_removed.size(), scope_name,
		core_unreachable.size(), optional_removed_display, dropped_note,
	]

func _new_template() -> void:
	core_edit.clear()
	optional_edit.clear()
	_name_edit.text = "new_template"
	_weight_spin.value = 1.0
	_keep_slider.value = 0.5
	_last_painted_cell = Vector2i(2147483647, 2147483647)
	_set_mode(PaintMode.CORE)
	_set_variant(0)
	_update_counts()
	_update_status("新建模板：在红边界内画 Core / Optional；绿=随机贴图")

func _save_current() -> void:
	var base := _name_edit.text.strip_edges().replace(" ", "_").trim_suffix(".tscn")
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		base = base.replace(ch, "_")
	if base == "":
		_update_status("保存失败：文件名不能为空")
		return
	if core_edit.get_used_cells().is_empty():
		_update_status("保存失败：Core 至少需要 1 格")
		return
	var path := TEMPLATE_DIR.path_join(base + ".tscn")
	if FileAccess.file_exists(path):
		_pending_save_path = path
		_save_dialog.dialog_text = "覆盖已有模板？\n%s" % path
		_save_dialog.popup_centered()
		return
	_save_to(path)

func _on_save_confirmed() -> void:
	if _pending_save_path != "":
		_save_to(_pending_save_path)

func _save_to(path: String) -> void:
	if not DirAccess.dir_exists_absolute(TEMPLATE_DIR):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMPLATE_DIR))
	var root := Node2D.new()
	root.name = "Template"
	root.set_script(load(TEMPLATE_SCRIPT))
	root.set("id", path.get_file().get_basename())
	root.set("weight", _weight_spin.value)
	root.set("optional_keep_chance", _keep_slider.value)
	var core_copy := core_edit.duplicate() as TileMapLayer
	if core_copy == null:
		root.free()
		_update_status("保存失败：Core 复制失败")
		return
	core_copy.name = "Core"
	core_copy.position = Vector2.ZERO
	core_copy.z_index = 0
	core_copy.modulate = Color.WHITE
	core_copy.collision_enabled = false
	root.add_child(core_copy)
	core_copy.owner = root
	var optional_copy := optional_edit.duplicate() as TileMapLayer
	if optional_copy != null:
		optional_copy.name = "Optional"
		optional_copy.position = Vector2.ZERO
		optional_copy.z_index = 0
		optional_copy.modulate = Color.WHITE
		optional_copy.collision_enabled = false
		root.add_child(optional_copy)
		optional_copy.owner = root
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	if pack_error != OK:
		root.free()
		_update_status("保存失败：pack error %d" % pack_error)
		return
	var save_error := ResourceSaver.save(packed, path)
	root.free()
	if save_error != OK:
		_update_status("保存失败：save error %d" % save_error)
		return
	_pending_save_path = ""
	_name_edit.text = path.get_file().get_basename()
	_refresh_template_list()
	_select_template(path.get_file().get_basename())
	_update_counts()
	_update_status("已保存：%s" % path)

func _load_selected() -> void:
	var selected := _template_list.get_selected_items()
	if selected.is_empty():
		_update_status("请先在列表中选择一个模板")
		return
	var index: int = selected[0]
	var key := _template_list.get_item_text(index)
	var path: String = _template_paths.get(key, "")
	if path == "":
		_update_status("读取失败：找不到模板路径")
		return
	_load_path(path)

func _delete_selected() -> void:
	var selected := _template_list.get_selected_items()
	if selected.is_empty():
		_update_status("请先在列表中选择要删除的模板")
		return
	var index: int = selected[0]
	var key := _template_list.get_item_text(index)
	var path: String = _template_paths.get(key, "")
	if path == "":
		_update_status("删除失败：找不到模板路径")
		return
	_pending_delete_path = path
	_delete_dialog.dialog_text = "删除模板？此操作不可撤销。\n%s" % path
	_delete_dialog.popup_centered()

func _on_delete_confirmed() -> void:
	if _pending_delete_path != "":
		_delete_path(_pending_delete_path)

func _delete_path(path: String) -> void:
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if err != OK:
		var dir := DirAccess.open(TEMPLATE_DIR)
		if dir != null:
			err = dir.remove(path.get_file())
	if err != OK:
		_update_status("删除失败：error %d\n%s" % [err, path])
		return
	var was_current := _name_edit.text == path.get_file().get_basename()
	_pending_delete_path = ""
	if was_current:
		_new_template()
	_refresh_template_list()
	_update_status("已删除：%s" % path)

func _load_path(path: String) -> void:
	var packed = load(path)
	if not (packed is PackedScene):
		_update_status("读取失败：不是 PackedScene：%s" % path)
		return
	var instance = (packed as PackedScene).instantiate()
	if instance == null:
		_update_status("读取失败：实例化失败：%s" % path)
		return
	core_edit.clear()
	optional_edit.clear()
	var core := instance.get_node_or_null("Core")
	if core is TileMapLayer:
		_copy_layer(core as TileMapLayer, core_edit)
	var optional := instance.get_node_or_null("Optional")
	if optional is TileMapLayer:
		_copy_layer(optional as TileMapLayer, optional_edit)
	# 兼容上一版独立 Random 层：迁移成 Core 的“随机贴图”格，保存后不再有 Random 层。
	var random := instance.get_node_or_null("Random")
	if random is TileMapLayer:
		_migrate_random_layer(random as TileMapLayer)
	_name_edit.text = path.get_file().get_basename()
	if instance is ObstacleMapTemplate:
		_weight_spin.value = (instance as ObstacleMapTemplate).weight
		_keep_slider.value = (instance as ObstacleMapTemplate).optional_keep_chance
	else:
		_weight_spin.value = 1.0
		_keep_slider.value = 0.5
	instance.free()
	_last_painted_cell = Vector2i(2147483647, 2147483647)
	_set_mode(PaintMode.CORE)
	_set_variant(0)
	_update_counts()
	_update_status("已读取：%s" % path)

func _copy_layer(source: TileMapLayer, target: TileMapLayer) -> void:
	for cell in source.get_used_cells():
		var source_id := source.get_cell_source_id(cell)
		if source_id == RANDOM_SOURCE_ID:
			target.set_cell(cell, RANDOM_SOURCE_ID, Vector2i(0, 0))
		else:
			var atlas := source.get_cell_atlas_coords(cell)
			target.set_cell(cell, SOURCE_ID, Vector2i(clampi(atlas.x, 0, 3), 0))

func _migrate_random_layer(random: TileMapLayer) -> void:
	var occupied := {}
	for cell in core_edit.get_used_cells():
		occupied[cell] = true
	for cell in optional_edit.get_used_cells():
		occupied[cell] = true
	for cell in random.get_used_cells():
		if not occupied.has(cell):
			core_edit.set_cell(cell, RANDOM_SOURCE_ID, Vector2i(0, 0))
			occupied[cell] = true

func _refresh_template_list() -> void:
	if _template_list == null:
		return
	var current := _name_edit.text if _name_edit != null else ""
	_template_list.clear()
	_template_paths.clear()
	var paths := _scan_template_paths()
	paths.sort()
	for path in paths:
		var key := path.get_file().get_basename()
		_template_paths[key] = path
		_template_list.add_item(key)
	if current != "":
		_select_template(current)

func _select_template(key: String) -> void:
	for i in _template_list.item_count:
		if _template_list.get_item_text(i) == key:
			_template_list.select(i)
			return

func _scan_template_paths() -> Array[String]:
	var out: Array[String] = []
	if DirAccess.dir_exists_absolute(TEMPLATE_DIR):
		for file in DirAccess.get_files_at(TEMPLATE_DIR):
			if file.ends_with(".tscn") and not file.begins_with("_"):
				out.append(TEMPLATE_DIR.path_join(file))
	if out.is_empty():
		for file in ResourceLoader.list_directory(TEMPLATE_DIR):
			if file.ends_with(".tscn") and not file.begins_with("_"):
				out.append(TEMPLATE_DIR.path_join(file))
	return out
