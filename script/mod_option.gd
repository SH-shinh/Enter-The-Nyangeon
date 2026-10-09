extends OptionMenu

# MOD 管理页：列出已安装 mod（名字 + 可选 icon + 启用开关），支持拖动 / 上下箭头调整顺序、
# 导入 zip；悬停 / 点按行显示描述 tooltip。顺序与启停一样下次重启生效（pck 挂载后不可卸载）。

const TOGGLE := preload("res://ui/option_toggle.tscn")
const ROW_FONT := preload("res://fonts/BoutiqueBitmap9x9_1.9.ttf")

const DRAG_THRESHOLD := 6.0
const ACCENT := Color(0.815686, 0.701961, 0.0235294, 1)

@onready var list_box: VBoxContainer = %List
@onready var list_scroll: ScrollContainer = %ScrollContainer
@onready var status_label: Label = %Status
@onready var import_btn: Button = %ImportBtn
@onready var up_btn: TextureButton = %UpBtn
@onready var down_btn: TextureButton = %DownBtn
@onready var drag_layer: Control = %DragLayer
@onready var tooltip: PanelContainer = %Tooltip
@onready var tip_name: Label = %TipName
@onready var tip_meta: Label = %TipMeta
@onready var tip_desc: Label = %TipDesc

var _file_dialog: FileDialog
var _pending_restart: bool = false
var _selected_id: String = ""
var _icon_cache: Dictionary = {}
var _touch_mode: bool = false
var _touch_tooltip_id: String = ""
var _tooltip_id: String = ""

var _press_row: Control = null
var _press_viewport: Vector2 = Vector2.ZERO
var _drag_grab_offset: Vector2 = Vector2.ZERO
var _drag_active: bool = false
var _drag_row: Control = null
var _spacer: Control = null


func _ready() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.use_native_dialog = true
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.zip", tr("mod_zip_filter"))
	_file_dialog.file_selected.connect(_on_zip_selected)
	add_child(_file_dialog)
	import_btn.pressed.connect(_on_import_pressed)
	up_btn.pressed.connect(func(): _move_selected(-1))
	down_btn.pressed.connect(func(): _move_selected(1))
	list_scroll.gui_input.connect(_on_list_scroll_gui_input)
	ModManager.mods_changed.connect(_refresh)
	_refresh()


func menu_show() -> void:
	super()
	_refresh()


func menu_hide() -> void:
	_cancel_drag()
	_clear_tooltip()
	super()


func _process(_delta: float) -> void:
	if not shown:
		return
	if _drag_active:
		_hide_tooltip()
		return
	if _touch_mode or _touch_tooltip_id != "":
		return
	var m := get_global_mouse_position()
	var row := _row_at(m)
	if row == null:
		_hide_tooltip()
		return
	var id := str(row.get_meta("mod_id", ""))
	if tooltip.visible and _tooltip_id == id:
		_place_tooltip(m)
	else:
		_show_tooltip(row, m)


func _refresh() -> void:
	if list_box == null:
		return
	_clear_tooltip()
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	for m in ModManager.list_mods():
		list_box.add_child(_make_row(m))
	if _pending_restart:
		status_label.text = tr("mod_restart_notice")
	_update_arrows()


func _make_row(m: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_constant_override("separation", 8)
	row.set_meta("mod_id", str(m.id))
	row.set_meta("mod_data", m)

	var bar := ColorRect.new()
	bar.name = "SelectBar"
	bar.color = ACCENT
	bar.custom_minimum_size = Vector2(3, 24)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = (str(m.id) == _selected_id)
	row.add_child(bar)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = _load_icon(str(m.icon))
	row.add_child(icon)

	var label := Label.new()
	label.name = "Name"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var suffix := ""
	if str(m.error) != "":
		suffix = "  " + (tr("mod_tag_error") % str(m.error))
	elif not m.mounted and m.enabled:
		suffix = "  " + tr("mod_tag_unmounted")
	label.text = "%s  v%s%s" % [str(m.name), str(m.version), suffix]
	_apply_row_font(label)
	row.add_child(label)

	var toggle = TOGGLE.instantiate()
	toggle.name = "Toggle"
	toggle.set("on", bool(m.enabled))
	toggle.connect("toggled", func(on: bool): _on_toggle(str(m.id), on))
	row.add_child(toggle)

	row.gui_input.connect(func(event: InputEvent): _on_row_gui_input(row, event))
	return row


func _apply_row_font(label: Label) -> void:
	label.add_theme_font_override("font", ROW_FONT)
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_constant_override("shadow_outline_size", 2)


func _load_icon(path: String) -> Texture2D:
	if path == "":
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	var tex: Texture2D = null
	if path.begins_with("res://"):
		tex = load(path)
	else:
		var img := Image.new()
		if img.load(path) == OK:
			tex = ImageTexture.create_from_image(img)
	_icon_cache[path] = tex
	return tex


# ---------------- 描述 tooltip ----------------

# 命中整行矩形（含开关），悬停/触摸用同一判定。
func _row_at(pos: Vector2) -> Control:
	for c in list_box.get_children():
		if c == _spacer or not (c is Control):
			continue
		if (c as Control).get_global_rect().has_point(pos):
			return c
	return null


func _show_tooltip(row: Control, pos: Vector2) -> void:
	var m: Dictionary = row.get_meta("mod_data", {})
	_tooltip_id = str(m.get("id", row.get_meta("mod_id", "")))
	tip_name.text = str(m.get("name", _tooltip_id))
	var ver := str(m.get("version", ""))
	var author := str(m.get("author", ""))
	var meta := ""
	if ver != "":
		meta = "v" + ver
	if author != "":
		meta = author if meta == "" else meta + "  " + author
	tip_meta.text = meta
	tip_meta.visible = meta != ""
	var desc := str(m.get("description", ""))
	tip_desc.text = desc
	tip_desc.visible = desc != ""
	tooltip.visible = true
	_place_tooltip(pos)


func _hide_tooltip() -> void:
	tooltip.visible = false
	_tooltip_id = ""


func _clear_tooltip() -> void:
	_touch_tooltip_id = ""
	_hide_tooltip()


# 跟随鼠标/触点，并夹在面板矩形内避免出屏。
func _place_tooltip(pos: Vector2) -> void:
	var area := get_global_rect()
	var tip_size := tooltip.get_combined_minimum_size()
	var p := pos + Vector2(16, 16)
	p.x = clampf(p.x, area.position.x, maxf(area.position.x, area.end.x - tip_size.x))
	p.y = clampf(p.y, area.position.y, maxf(area.position.y, area.end.y - tip_size.y))
	tooltip.global_position = p


# 触屏：点同一行收起，点另一行切换。
func _toggle_touch_tooltip(row: Control) -> void:
	var id := str(row.get_meta("mod_id", ""))
	if _touch_tooltip_id == id:
		_clear_tooltip()
	else:
		_touch_tooltip_id = id
		_show_tooltip(row, row.global_position + Vector2(row.size.x + 8.0, 0.0))


# 点列表空白处（未落在任何行）收起触摸 tooltip。
func _on_list_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and _touch_tooltip_id != "":
		var gpos: Vector2 = list_scroll.get_global_transform_with_canvas() * event.position
		if _row_at(gpos) == null:
			_clear_tooltip()


# ---------------- 选中 / 上下箭头 ----------------

func _selected_index() -> int:
	if _selected_id == "":
		return -1
	for i in list_box.get_child_count():
		if str(list_box.get_child(i).get_meta("mod_id", "")) == _selected_id:
			return i
	return -1


func _select(row: Control) -> void:
	_selected_id = str(row.get_meta("mod_id", ""))
	for c in list_box.get_children():
		var bar := c.get_node_or_null("SelectBar")
		if bar != null:
			bar.visible = (str(c.get_meta("mod_id", "")) == _selected_id)
	_update_arrows()


func _update_arrows() -> void:
	var idx := _selected_index()
	up_btn.disabled = idx <= 0
	down_btn.disabled = idx < 0 or idx >= list_box.get_child_count() - 1


func _current_ids() -> Array:
	var ids: Array = []
	for c in list_box.get_children():
		if c == _spacer:
			continue
		ids.append(str(c.get_meta("mod_id", "")))
	return ids


func _move_selected(delta: int) -> void:
	var idx := _selected_index()
	var target := idx + delta
	if idx < 0 or target < 0 or target >= list_box.get_child_count():
		return
	var ids := _current_ids()
	var tmp = ids[idx]
	ids[idx] = ids[target]
	ids[target] = tmp
	_pending_restart = true
	ModManager.set_order(ids)
	_update_arrows()


# ---------------- 行输入 / 拖动排序 ----------------

func _on_row_gui_input(row: Control, event: InputEvent) -> void:
	if _drag_active:
		return
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = true
	if not pressed:
		return
	row.accept_event()
	_press_row = row
	_press_viewport = row.get_global_transform() * event.position
	_drag_grab_offset = _press_viewport - row.global_position


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch_mode = true
	elif event is InputEventMouse and event.device != InputEvent.DEVICE_ID_EMULATION:
		_touch_mode = false
	if _press_row == null or not is_instance_valid(_press_row):
		return
	if _drag_active:
		var p := _event_viewport_pos(event)
		if p != Vector2.INF:
			_drag_row.global_position = p - _drag_grab_offset
			_move_spacer_to(_target_index(p.y))
		if _is_release(event):
			_end_drag()
			_press_row = null
		get_viewport().set_input_as_handled()
		return
	var p2 := _event_viewport_pos(event)
	if p2 != Vector2.INF and p2.distance_to(_press_viewport) > DRAG_THRESHOLD:
		_start_drag()
		get_viewport().set_input_as_handled()
		return
	if _is_release(event):
		var released: Control = _press_row
		_select(released)
		_press_row = null
		if event is InputEventScreenTouch:
			_toggle_touch_tooltip(released)


func _event_viewport_pos(event: InputEvent) -> Vector2:
	if event is InputEventScreenDrag:
		return event.position
	if event is InputEventScreenTouch:
		return event.position
	if event is InputEventMouseMotion:
		return event.position
	return Vector2.INF


func _is_release(event: InputEvent) -> bool:
	if event is InputEventScreenTouch and not event.pressed:
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		return true
	return false


func _start_drag() -> void:
	_clear_tooltip()
	_drag_active = true
	_drag_row = _press_row
	var h := _drag_row.size.y
	_spacer = Control.new()
	_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spacer.custom_minimum_size = Vector2(0, h)
	_spacer.size = Vector2(0, h)
	var idx := _drag_row.get_index()
	list_box.add_child(_spacer)
	list_box.move_child(_spacer, idx)
	list_box.remove_child(_drag_row)
	drag_layer.add_child(_drag_row)
	_drag_row.size = Vector2(list_box.size.x, h)
	_drag_row.global_position = _press_viewport - _drag_grab_offset


func _move_spacer_to(target: int) -> void:
	if _spacer == null or not is_instance_valid(_spacer):
		return
	target = clampi(target, 0, list_box.get_child_count() - 1)
	if _spacer.get_index() != target:
		list_box.move_child(_spacer, target)


func _target_index(y: float) -> int:
	var idx := 0
	for c in list_box.get_children():
		if y > c.global_position.y + c.size.y * 0.5:
			idx += 1
		else:
			break
	return idx


func _end_drag() -> void:
	_drag_active = false
	var idx := _spacer.get_index()
	var id := str(_drag_row.get_meta("mod_id", ""))
	var p := _drag_row.get_parent()
	if p != null:
		p.remove_child(_drag_row)
	list_box.add_child(_drag_row)
	list_box.move_child(_drag_row, idx)
	list_box.remove_child(_spacer)
	_spacer.queue_free()
	_spacer = null
	_drag_row = null
	_selected_id = id
	_pending_restart = true
	ModManager.set_order(_current_ids())


func _cancel_drag() -> void:
	_press_row = null
	if not _drag_active:
		return
	_drag_active = false
	if _spacer != null and is_instance_valid(_spacer):
		var idx := _spacer.get_index()
		var p := _drag_row.get_parent()
		if p != null:
			p.remove_child(_drag_row)
		list_box.add_child(_drag_row)
		list_box.move_child(_drag_row, idx)
		list_box.remove_child(_spacer)
		_spacer.queue_free()
	_spacer = null
	_drag_row = null


# ---------------- 启停 / 导入 ----------------

func _on_toggle(id: String, on: bool) -> void:
	ModManager.set_enabled(id, on)
	_pending_restart = true
	status_label.text = tr("mod_restart_notice")


func _on_import_pressed() -> void:
	_file_dialog.popup_centered_ratio()


func _on_zip_selected(path: String) -> void:
	var r := ModManager.import_zip(path)
	if r.get("ok", false):
		_pending_restart = true
		status_label.text = tr("mod_import_ok") % str(r.get("id", ""))
	else:
		status_label.text = tr("mod_import_fail") % str(r.get("error", ""))
	_refresh()
