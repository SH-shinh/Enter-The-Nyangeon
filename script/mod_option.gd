extends OptionMenu

const TOGGLE := preload("res://ui/option_toggle.tscn")
const ROW_FONT := preload("res://fonts/BoutiqueBitmap9x9_1.9.ttf")

const DRAG_THRESHOLD := 6.0
const ACCENT := Color(0.815686, 0.701961, 0.0235294, 1)
const DANGER := Color(1.0, 0.352941, 0.352941, 1)
const OK_COLOR := Color(0.509804, 0.807843, 0.313726, 1)
const DIM := Color(0.74902, 0.74902, 0.74902, 1)
# 拖入结果浮层：停留时长 + 淡出时长（秒）。
const TOAST_HOLD := 2.6
const TOAST_FADE := 0.4

@onready var list_box: VBoxContainer = %List
@onready var summary_label: AutoText = %Summary
@onready var status_label: Label = %Status
@onready var import_btn: Button = %ImportBtn
@onready var restart_bar: PanelContainer = %RestartBar
@onready var restart_label: AutoText = %RestartLabel
@onready var undo_btn: Button = %UndoBtn
@onready var restart_btn: Button = %RestartBtn
@onready var uninstall_btn: Button = %UninstallBtn
@onready var up_btn: Button = %UpBtn
@onready var down_btn: Button = %DownBtn
@onready var drag_layer: Control = %DragLayer
@onready var detail_head: HBoxContainer = %DetailHead
@onready var detail_buttons: HBoxContainer = %DetailButtons
@onready var empty_label: Label = %EmptyLabel
@onready var detail_scroll: ScrollContainer = %DetailScroll
@onready var detail_icon: TextureRect = %Icon
@onready var detail_initial: Label = %Initial
@onready var detail_name: Label = %DetailName
@onready var detail_meta: Label = %DetailMeta
@onready var detail_error: Label = %DetailError
@onready var detail_desc: Label = %DetailDesc
@onready var detail_deps: Label = %DetailDeps
@onready var detail_adds: Label = %DetailAdds
@onready var detail_override_scripts: Label = %DetailOverrideScripts
@onready var detail_overrides: Label = %DetailOverrides
@onready var detail_min_version: Label = %DetailMinVersion
@onready var detail_min_state: Label = %DetailMinState
@onready var detail_dir: Label = %DetailDir

var _file_dialog: FileDialog
var _confirm: ConfirmationDialog
var _restart_confirm: ConfirmationDialog
var _selected_id: String = ""
var _icon_cache: Dictionary = {}
var _last_mods: Array = []
var _pending_ids: Dictionary = {}
var _pending_irreversible: Dictionary = {}
var _baseline_valid: bool = false
var _baseline_enabled: Dictionary = {}
var _baseline_order: Array = []
var _baseline_ids: Array = []
var _restoring: bool = false
var _row_hover_id: String = ""

var _row_style_normal: StyleBoxFlat
var _row_style_hover: StyleBoxFlat
var _row_style_selected: StyleBoxFlat
var _row_icon_style: StyleBoxFlat

var _press_row: Control = null
var _press_touch_index: int = -1
var _press_viewport: Vector2 = Vector2.ZERO
var _drag_grab_offset: Vector2 = Vector2.ZERO
var _drag_active: bool = false
var _drag_row: Control = null
var _drag_origin_index: int = 0
var _drag_origin_row_index: int = 0
var _spacer: Control = null

var _drop_hint: Label
var _drop_toast: PanelContainer
var _drop_toast_label: Label
var _drop_toast_tween: Tween
# 同一文件列表在 1 秒内重复触发时只处理一次（防止一次拖放被重复回调）。
# 不用 static：GDScript 静态变量会让脚本类在退出时无法释放，连带 preload 资源计入退出泄漏。
var _last_drop_sig: String = ""
var _last_drop_msec: int = 0


func _ready() -> void:
	_build_row_styles()
	_build_drop_hint()
	_build_drop_toast()
	_file_dialog = FileDialog.new()
	_file_dialog.use_native_dialog = true
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.zip", tr("mod_zip_filter"))
	_file_dialog.file_selected.connect(_on_zip_selected)
	add_child(_file_dialog)
	import_btn.pressed.connect(_on_import_pressed)
	uninstall_btn.pressed.connect(_on_uninstall_pressed)
	_confirm = ConfirmationDialog.new()
	_confirm.title = tr("mod_uninstall")
	_confirm.ok_button_text = tr("mod_uninstall")
	_confirm.cancel_button_text = tr("mod_cancel")
	add_child(_confirm)
	_confirm.confirmed.connect(_on_uninstall_confirmed)
	_restart_confirm = ConfirmationDialog.new()
	_restart_confirm.title = tr("mod_restart_now")
	_restart_confirm.ok_button_text = tr("mod_restart_now")
	_restart_confirm.cancel_button_text = tr("mod_cancel")
	_restart_confirm.dialog_text = tr("mod_restart_confirm")
	add_child(_restart_confirm)
	_restart_confirm.confirmed.connect(_on_restart_confirmed)
	up_btn.pressed.connect(func(): _move_selected(-1))
	down_btn.pressed.connect(func(): _move_selected(1))
	undo_btn.pressed.connect(_on_undo)
	restart_btn.pressed.connect(_on_restart_pressed)
	ModManager.mods_changed.connect(_refresh)
	_refresh()


func menu_show() -> void:
	super()
	_set_status("")
	_refresh()


func menu_hide() -> void:
	_cancel_drag()
	_hide_drop_toast()
	super()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel_drag()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_update_summary()
		_update_restart_bar()
		if _drop_hint != null:
			_drop_hint.text = tr("mod_drop_hint")
			LocaleFont.apply_control(_drop_hint)


func _build_row_styles() -> void:
	_row_style_normal = StyleBoxFlat.new()
	_row_style_normal.bg_color = Color(0.164706, 0.164706, 0.164706, 1)
	_row_style_normal.content_margin_left = 3.0
	_row_style_normal.content_margin_right = 3.0
	_row_style_normal.content_margin_top = 1.0
	_row_style_normal.content_margin_bottom = 1.0
	_row_style_hover = StyleBoxFlat.new()
	_row_style_hover.bg_color = Color(0.196078, 0.196078, 0.196078, 1)
	_row_style_hover.content_margin_left = 3.0
	_row_style_hover.content_margin_right = 3.0
	_row_style_hover.content_margin_top = 1.0
	_row_style_hover.content_margin_bottom = 1.0
	_row_style_hover.border_width_left = 1
	_row_style_hover.border_width_top = 1
	_row_style_hover.border_width_right = 1
	_row_style_hover.border_width_bottom = 1
	_row_style_hover.border_color = Color(0.372549, 0.372549, 0.372549, 1)
	_row_style_selected = StyleBoxFlat.new()
	_row_style_selected.bg_color = Color(0.211765, 0.211765, 0.211765, 1)
	_row_style_selected.content_margin_left = 3.0
	_row_style_selected.content_margin_right = 3.0
	_row_style_selected.content_margin_top = 1.0
	_row_style_selected.content_margin_bottom = 1.0
	_row_style_selected.border_width_left = 1
	_row_style_selected.border_width_top = 1
	_row_style_selected.border_width_right = 1
	_row_style_selected.border_width_bottom = 1
	_row_style_selected.border_color = ACCENT
	_row_icon_style = StyleBoxFlat.new()
	_row_icon_style.bg_color = Color(0.121569, 0.121569, 0.121569, 1)
	_row_icon_style.border_width_left = 1
	_row_icon_style.border_width_top = 1
	_row_icon_style.border_width_right = 1
	_row_icon_style.border_width_bottom = 1
	_row_icon_style.border_color = Color(0.294118, 0.294118, 0.294118, 1)


func _refresh() -> void:
	if list_box == null or _restoring:
		return
	var focused := get_viewport().gui_get_focus_owner()
	var focus_id := ""
	var focus_toggle := false
	for row in _row_children():
		if focused != null and (row == focused or row.is_ancestor_of(focused)):
			focus_id = str(row.get_meta("mod_id"))
			focus_toggle = row != focused
			break
	_cancel_drag()
	_row_hover_id = ""
	for c in list_box.get_children():
		list_box.remove_child(c)
		c.queue_free()
	_last_mods = ModManager.list_mods()
	_sync_pending()
	var groups := {
		"attention": [],
		"enabled": [],
		"disabled": [],
	}
	var known: Dictionary = {}
	for m in _last_mods:
		var id := str(m.id)
		known[id] = true
		groups[_group_key(m)].append(m)
	if not known.has(_selected_id):
		_selected_id = str(_last_mods[0].id) if not _last_mods.is_empty() else ""
	for key in ["attention", "enabled", "disabled"]:
		var items: Array = groups[key]
		if items.is_empty():
			continue
		list_box.add_child(_make_group_header(key, items.size()))
		for m in items:
			list_box.add_child(_make_row(m))
	_update_summary()
	_update_restart_bar()
	_update_arrows()
	_update_detail()
	_bind_row_navigation()
	if focus_id != "":
		_restore_row_focus.call_deferred(focus_id, focus_toggle)


func _group_key(m: Dictionary) -> String:
	if str(m.get("error", "")) != "":
		return "attention"
	var required := str(m.get("game_version", ""))
	if required != "" and not bool(m.get("game_version_ok", true)):
		return "attention"
	return "enabled" if bool(m.get("enabled", false)) else "disabled"


func _make_group_header(key: String, count: int) -> Label:
	var label := Label.new()
	label.set_meta("group_header", true)
	label.custom_minimum_size = Vector2(0, 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ROW_FONT)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", DANGER if key == "attention" else DIM)
	var text_key := "mod_group_attention"
	if key == "enabled":
		text_key = "mod_group_enabled"
	elif key == "disabled":
		text_key = "mod_group_disabled"
	label.text = tr(text_key) % count
	return label


func _make_row(m: Dictionary) -> PanelContainer:
	var id := str(m.id)
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 22)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.focus_mode = Control.FOCUS_ALL
	row.set_meta("mod_id", id)
	row.set_meta("mod_data", m)
	row.set_meta("is_row", true)
	row.add_theme_stylebox_override("panel", _row_style_for(id))

	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	row.add_child(box)

	var icon_slot := PanelContainer.new()
	icon_slot.custom_minimum_size = Vector2(20, 20)
	icon_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_slot.add_theme_stylebox_override("panel", _row_icon_style)
	box.add_child(icon_slot)

	var icon := TextureRect.new()
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := _load_icon(str(m.get("icon", "")))
	icon.texture = tex
	icon.visible = tex != null
	icon_slot.add_child(icon)

	var initial := Label.new()
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.add_theme_font_override("font", ROW_FONT)
	initial.add_theme_font_size_override("font_size", 10)
	initial.add_theme_color_override("font_color", ACCENT)
	initial.text = _name_initial(str(m.get("name", id)), id)
	initial.visible = tex == null
	icon_slot.add_child(initial)

	var text_box := VBoxContainer.new()
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.add_theme_constant_override("separation", 0)
	box.add_child(text_box)
	var label := Label.new()
	label.name = "Name"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = str(m.get("name", id))
	_apply_row_font(label)
	text_box.add_child(label)

	var pending := Label.new()
	pending.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pending.add_theme_font_override("font", ROW_FONT)
	pending.add_theme_font_size_override("font_size", 8)
	pending.add_theme_color_override("font_color", ACCENT)
	pending.text = tr("mod_detail_pending")
	pending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pending.visible = _is_pending(id)
	text_box.add_child(pending)

	var toggle = TOGGLE.instantiate()
	toggle.name = "Toggle"
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.set("on", bool(m.get("enabled", false)))
	toggle.connect("toggled", func(on: bool): _on_toggle(id, on))
	box.add_child(toggle)
	row.focus_entered.connect(func(): _focus_row(row))
	toggle.focus_entered.connect(func(): _focus_row(row))
	toggle.gui_input.connect(func(event: InputEvent): _on_row_key_input(row, event, true))

	row.mouse_entered.connect(func(): _on_row_hover(row, true))
	row.mouse_exited.connect(func(): _on_row_hover(row, false))
	row.gui_input.connect(func(event: InputEvent): _on_row_gui_input(row, event))
	return row


func _focus_row(row: Control) -> void:
	_select(row)
	(list_box.get_parent() as ScrollContainer).ensure_control_visible(row)


func _restore_row_focus(id: String, to_toggle: bool) -> void:
	if not shown:
		return
	for row in _row_children():
		if str(row.get_meta("mod_id")) == id:
			var target: Control = row.find_child("Toggle", true, false) if to_toggle else row
			target.grab_focus()
			return


func _bind_row_navigation() -> void:
	var rows := _row_children()
	import_btn.focus_next = NodePath("")
	import_btn.focus_neighbor_bottom = NodePath("")
	if rows.is_empty():
		return
	import_btn.focus_neighbor_bottom = import_btn.get_path_to(rows[0])
	for i in rows.size():
		var row: Control = rows[i]
		var toggle: Control = row.find_child("Toggle", true, false)
		var previous: Control = import_btn if i == 0 else rows[i - 1].find_child("Toggle", true, false)
		var next: Control = rows[i + 1] if i + 1 < rows.size() else uninstall_btn
		row.focus_previous = row.get_path_to(previous)
		row.focus_next = row.get_path_to(toggle)
		toggle.focus_previous = toggle.get_path_to(row)
		toggle.focus_next = toggle.get_path_to(next)
	import_btn.focus_next = import_btn.get_path_to(rows[0])


func _on_row_key_input(row: Control, event: InputEvent, from_toggle: bool = false) -> void:
	var direction := 0
	if event.is_action_pressed("ui_up"):
		direction = -1
	elif event.is_action_pressed("ui_down"):
		direction = 1
	if direction != 0:
		var rows := _row_children()
		var index := rows.find(row) + direction
		if index >= 0 and index < rows.size():
			var target: Control = rows[index].find_child("Toggle", true, false) if from_toggle else rows[index]
			target.grab_focus()
		elif index < 0:
			import_btn.grab_focus()
		else:
			uninstall_btn.grab_focus()
		row.accept_event()
	elif event.is_action_pressed("ui_right") and not from_toggle:
		(row.find_child("Toggle", true, false) as Control).grab_focus()
		row.accept_event()
	elif event.is_action_pressed("ui_left") and from_toggle:
		row.grab_focus()
		row.accept_event()
	elif event.is_action_pressed("ui_accept") and not from_toggle:
		row.accept_event()
		_on_toggle(str(row.get_meta("mod_id")), not bool(row.get_meta("mod_data").get("enabled", false)))


func _apply_row_font(label: Label) -> void:
	label.add_theme_font_override("font", ROW_FONT)
	label.add_theme_font_size_override("font_size", 12)
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


func _row_style_for(id: String) -> StyleBoxFlat:
	if id == _selected_id:
		return _row_style_selected
	if id == _row_hover_id:
		return _row_style_hover
	return _row_style_normal


func _apply_row_style(row: Control) -> void:
	row.add_theme_stylebox_override("panel", _row_style_for(str(row.get_meta("mod_id", ""))))


func _on_row_hover(row: Control, entered: bool) -> void:
	if _drag_active:
		return
	_row_hover_id = str(row.get_meta("mod_id", "")) if entered else ""
	for c in _row_children():
		_apply_row_style(c)


func _row_children() -> Array:
	var out: Array = []
	for c in list_box.get_children():
		if c.has_meta("is_row"):
			out.append(c)
	return out


func _select(row: Control) -> void:
	var id := str(row.get_meta("mod_id", ""))
	if id == _selected_id:
		return
	_selected_id = id
	detail_scroll.scroll_vertical = 0
	for c in _row_children():
		_apply_row_style(c)
	_update_arrows()
	_update_detail()


func _update_arrows() -> void:
	var ids := _displayed_ids()
	var pos := ids.find(_selected_id)
	up_btn.disabled = pos <= 0
	down_btn.disabled = pos < 0 or pos >= ids.size() - 1
	uninstall_btn.disabled = _selected_id == ""


func _current_ids() -> Array:
	# list_mods 已按用户顺序排序；分组后的节点顺序只用于定位操作目标。
	var ids: Array = []
	for m in _last_mods:
		ids.append(str(m.id))
	return ids


func _displayed_ids() -> Array:
	var ids: Array = []
	for c in _row_children():
		ids.append(str(c.get_meta("mod_id", "")))
	return ids


func _move_selected(delta: int) -> void:
	var ids := _displayed_ids()
	var pos := ids.find(_selected_id)
	var target := pos + delta
	if pos < 0 or target < 0 or target >= ids.size():
		return
	_move_mod(_selected_id, str(ids[target]), delta < 0)


func _move_mod(id: String, anchor: String, before: bool) -> bool:
	var current := _current_ids()
	if id == anchor or not current.has(id) or not current.has(anchor):
		return false
	var next := current.duplicate()
	next.erase(id)
	next.insert(next.find(anchor) + (0 if before else 1), id)
	if next == current:
		return false
	_ensure_baseline()
	ModManager.set_order(next)
	return true


func _on_row_gui_input(row: Control, event: InputEvent) -> void:
	if _drag_active:
		return
	_on_row_key_input(row, event)
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		if _press_row != null:
			return
		pressed = true
		_press_touch_index = event.index
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		pressed = true
		_press_touch_index = -1
	if not pressed:
		return
	# 触屏按下继续传给 ScrollContainer；鼠标仍保留整行拖动排序。
	if _press_touch_index < 0:
		row.accept_event()
		row.grab_focus()
	_press_row = row
	_press_viewport = row.get_global_transform() * event.position
	_drag_grab_offset = _press_viewport - row.global_position


func _input(event: InputEvent) -> void:
	if _press_row == null or not is_instance_valid(_press_row):
		return
	if _press_touch_index >= 0:
		if event is InputEventScreenDrag and event.index == _press_touch_index:
			if event.position.distance_to(_press_viewport) > DRAG_THRESHOLD:
				_press_row = null
				_press_touch_index = -1
		elif event is InputEventScreenTouch and event.index == _press_touch_index and not event.pressed:
			if not event.canceled:
				_select(_press_row)
				_press_row.grab_focus()
			_press_row = null
			_press_touch_index = -1
		return
	if _drag_active:
		var p := _event_viewport_pos(event)
		if p != Vector2.INF:
			_drag_row.global_position = p - _drag_grab_offset
			_move_spacer_to(_target_row_index(p.y))
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
	_ensure_baseline()
	_drag_active = true
	_drag_row = _press_row
	_drag_origin_index = _drag_row.get_index()
	_drag_origin_row_index = _row_children().find(_drag_row)
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
	var rows := _row_children()
	target = clampi(target, 0, rows.size())
	var child_idx := list_box.get_child_count()
	if target < rows.size():
		child_idx = rows[target].get_index()
	if _spacer.get_index() < child_idx:
		child_idx -= 1
	child_idx = clampi(child_idx, 0, list_box.get_child_count() - 1)
	if _spacer.get_index() != child_idx:
		list_box.move_child(_spacer, child_idx)


func _target_row_index(y: float) -> int:
	var idx := 0
	for row in _row_children():
		if y > row.global_position.y + row.size.y * 0.5:
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
	_press_row = null
	_selected_id = id
	var ids := _displayed_ids()
	var target := ids.find(id)
	var changed := false
	# 只移动拖动项，保留其余 Mod 的全局相对顺序，避免分组改写冲突优先级。
	if target > _drag_origin_row_index:
		changed = _move_mod(id, str(ids[target - 1]), false)
	elif target < _drag_origin_row_index:
		changed = _move_mod(id, str(ids[target + 1]), true)
	if not changed:
		_refresh()


func _cancel_drag() -> void:
	_press_row = null
	_press_touch_index = -1
	if not _drag_active:
		return
	_drag_active = false
	if _spacer != null and is_instance_valid(_spacer):
		var p := _drag_row.get_parent()
		if p != null:
			p.remove_child(_drag_row)
		list_box.remove_child(_spacer)
		_spacer.queue_free()
		_spacer = null
		var idx := clampi(_drag_origin_index, 0, list_box.get_child_count())
		list_box.add_child(_drag_row)
		list_box.move_child(_drag_row, idx)
	_drag_row = null


func _update_summary() -> void:
	var effective := 0
	for m in _last_mods:
		if bool(m.get("mounted", false)) and str(m.get("error", "")) == "":
			effective += 1
	summary_label.text = tr("mod_summary") % [_last_mods.size(), effective, _pending_count()]
	summary_label.refit()


func _update_restart_bar() -> void:
	var count := _pending_count()
	restart_bar.visible = count > 0
	restart_label.text = tr("mod_restart_bar") % count
	restart_label.refit()
	undo_btn.disabled = _pending_ids.is_empty()


func _pending_count() -> int:
	var all: Dictionary = {}
	for id in _pending_ids:
		all[str(id)] = true
	for id in _pending_irreversible:
		all[str(id)] = true
	return all.size()


func _is_pending(id: String) -> bool:
	return _pending_ids.has(id) or _pending_irreversible.has(id)


func _ensure_baseline() -> void:
	if _baseline_valid:
		return
	_baseline_valid = true
	_baseline_enabled.clear()
	for m in ModManager.list_mods():
		_baseline_enabled[str(m.id)] = bool(m.enabled)
	_baseline_order = ModManager.get_order()
	_baseline_ids = _current_ids()


func _sync_pending() -> void:
	_pending_ids.clear()
	if not _baseline_valid:
		return
	var current: Array = []
	for m in _last_mods:
		var id := str(m.id)
		if not _baseline_enabled.has(id):
			continue
		current.append(id)
		if bool(m.enabled) != bool(_baseline_enabled[id]):
			_pending_ids[id] = true
	# 导入/卸载单独记录；比较仍在安装的基线项，避免增删项造成伪排序改动。
	var baseline: Array = []
	for id in _baseline_ids:
		if current.has(id):
			baseline.append(id)
	for i in current.size():
		if current[i] != baseline[i]:
			_pending_ids[str(current[i])] = true


func _on_toggle(id: String, on: bool) -> void:
	_ensure_baseline()
	ModManager.set_enabled(id, on)


func _on_undo() -> void:
	if not _baseline_valid or _pending_ids.is_empty():
		return
	_restoring = true
	for id in _baseline_enabled:
		ModManager.set_enabled(str(id), bool(_baseline_enabled[id]))
	ModManager.set_order(_baseline_order)
	_pending_ids.clear()
	_baseline_valid = false
	_restoring = false
	_set_status("")
	_refresh()


func _on_restart_pressed() -> void:
	_restart_confirm.popup_centered()


func _on_restart_confirmed() -> void:
	get_tree().quit()


func _on_import_pressed() -> void:
	_file_dialog.popup_centered_ratio()


func _on_zip_selected(path: String) -> void:
	var r := ModManager.import_zip(path)
	if r.get("ok", false):
		var id := str(r.get("id", ""))
		if id != "":
			_pending_irreversible[id] = true
		_set_status(tr("mod_import_ok") % id)
	else:
		_set_status(tr("mod_import_fail") % str(r.get("error", "")), true)
	_refresh()


# ---------------- 系统拖放导入 ----------------

# 由 ui/option.gd 在当前页可见时转发；页面未展开时直接忽略。
func handle_files_dropped(files: PackedStringArray) -> void:
	if not shown:
		return
	var zips := _zip_paths(files)
	var sig := "|".join(zips)
	var now := Time.get_ticks_msec()
	if not zips.is_empty() and sig == _last_drop_sig and now - _last_drop_msec < 1000:
		return
	_last_drop_sig = sig
	_last_drop_msec = now
	if zips.is_empty():
		var message := tr("mod_drop_no_zip")
		_set_status(message, true)
		_show_drop_toast(message, true)
		return
	_show_drop_toast(_tr_format("mod_drop_importing", zips.size()))
	_install_dropped_zips.call_deferred(zips)


# 过滤出可安装的 zip（忽略非 zip、目录、不存在的路径、重复项）。
func _zip_paths(files: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var seen: Dictionary = {}
	for f in files:
		var path := str(f)
		if path.get_extension().to_lower() != "zip":
			continue
		if seen.has(path) or DirAccess.dir_exists_absolute(path) or not FileAccess.file_exists(path):
			continue
		seen[path] = true
		out.append(path)
	return out


func _install_dropped_zips(zips: PackedStringArray) -> void:
	if not is_inside_tree():
		return
	var result: Dictionary = ModManager.import_zip_files(zips)
	var imported: Array = result.get("imported", [])
	var failed: Array = result.get("failed", [])
	for item in imported:
		var id := str(item.get("id", ""))
		if id != "":
			_pending_irreversible[id] = true
	var message := _drop_result_text(imported, failed)
	var good := failed.is_empty() and not imported.is_empty()
	_set_status(message, not good)
	_show_drop_toast(message, not good)
	_refresh()


func _drop_result_text(imported: Array, failed: Array) -> String:
	if imported.size() == 1 and failed.is_empty():
		return _tr_format("mod_import_ok", str(imported[0].get("id", "")))
	var parts := PackedStringArray()
	if not imported.is_empty():
		parts.append(_tr_format("mod_drop_ok", imported.size()))
	if not failed.is_empty():
		var details := PackedStringArray()
		for i in mini(failed.size(), 2):
			var item: Dictionary = failed[i]
			details.append("%s: %s" % [str(item.get("path", "")).get_file(), str(item.get("error", ""))])
		if failed.size() > 2:
			details.append("...")
		parts.append(_tr_format("mod_drop_fail", " / ".join(details)))
	if parts.is_empty():
		return tr("mod_drop_no_zip")
	return "\n".join(parts)


# 翻译缺失时 tr() 返回键名（无占位符），直接格式化会抛 String formatting error，这里先判占位符。
func _tr_format(key: String, values) -> String:
	var text := tr(key)
	if not text.contains("%"):
		return text
	return text % values


func _build_drop_hint() -> void:
	var hint := Label.new()
	hint.text = tr("mod_drop_hint")
	if hint.text == "mod_drop_hint" or status_label == null:
		return
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_override("font", ROW_FONT)
	hint.add_theme_font_size_override("font_size", 9)
	hint.add_theme_color_override("font_color", DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var content := status_label.get_parent()
	if content == null:
		return
	_drop_hint = hint
	content.add_child(hint)
	content.move_child(hint, status_label.get_index() + 1)


func _build_drop_toast() -> void:
	var panel := PanelContainer.new()
	panel.visible = false
	panel.z_index = 20
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0745098, 0.0745098, 0.0745098, 0.95)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = OK_COLOR
	style.content_margin_left = 6.0
	style.content_margin_top = 3.0
	style.content_margin_right = 6.0
	style.content_margin_bottom = 3.0
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", ROW_FONT)
	label.add_theme_font_size_override("font_size", 10)
	panel.add_child(label)
	add_child(panel)
	_drop_toast = panel
	_drop_toast_label = label


func _show_drop_toast(text: String, failed: bool = false) -> void:
	if _drop_toast == null or _drop_toast_label == null:
		return
	if _drop_toast_tween != null and _drop_toast_tween.is_valid():
		_drop_toast_tween.kill()
	_drop_toast_label.text = text
	LocaleFont.apply_control(_drop_toast_label)
	# 短文案单行、按内容撑宽；长文案（批量失败明细/多行）固定宽度并自动换行。
	var wrap := text.length() > 28 or text.contains("\n")
	_drop_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	_drop_toast_label.custom_minimum_size = Vector2(380.0 if wrap else 0.0, 0.0)
	var style := _drop_toast.get_theme_stylebox("panel") as StyleBoxFlat
	if style != null:
		style.border_color = DANGER if failed else OK_COLOR
	_drop_toast.modulate.a = 1.0
	_drop_toast.visible = true
	_place_drop_toast()
	_place_drop_toast.call_deferred()
	_drop_toast_tween = create_tween()
	_drop_toast_tween.tween_interval(TOAST_HOLD)
	_drop_toast_tween.tween_property(_drop_toast, "modulate:a", 0.0, TOAST_FADE)
	_drop_toast_tween.tween_callback(_on_drop_toast_expired)


func _place_drop_toast() -> void:
	if _drop_toast == null or not _drop_toast.visible:
		return
	_drop_toast.reset_size()
	_drop_toast.position = Vector2(
		(size.x - _drop_toast.size.x) * 0.5,
		maxf(0.0, size.y - _drop_toast.size.y - 10.0),
	)


func _on_drop_toast_expired() -> void:
	if _drop_toast != null:
		_drop_toast.visible = false
	_drop_toast_tween = null


func _hide_drop_toast() -> void:
	if _drop_toast_tween != null and _drop_toast_tween.is_valid():
		_drop_toast_tween.kill()
	_drop_toast_tween = null
	if _drop_toast != null:
		_drop_toast.visible = false


func _on_uninstall_pressed() -> void:
	if _selected_id == "":
		_set_status(tr("mod_uninstall_select"), true)
		return
	var name := _mod_display_name(_selected_id)
	_confirm.dialog_text = tr("mod_uninstall_confirm") % name
	_confirm.popup_centered()


func _on_uninstall_confirmed() -> void:
	var id := _selected_id
	if id == "":
		return
	var name := _mod_display_name(id)
	_selected_id = ""
	var r := ModManager.uninstall(id)
	if not r.get("ok", false):
		_refresh()
		_set_status(tr("mod_uninstall_fail") % str(r.get("error", "")), true)
		return
	_pending_ids.erase(id)
	if bool(r.get("restart_required", false)) or not bool(r.get("deleted", false)):
		_pending_irreversible[id] = true
	else:
		_pending_irreversible.erase(id)
	var message := tr("mod_uninstall_ok") % name if bool(r.get("deleted", false)) else tr("mod_uninstall_pending")
	if bool(r.get("restart_required", false)):
		message += "  " + tr("mod_restart_notice")
	_set_status(message)
	_refresh()


func _set_status(message: String, failed: bool = false) -> void:
	status_label.text = message
	status_label.visible = message != ""
	status_label.add_theme_color_override("font_color", DANGER if failed else OK_COLOR)


func _mod_display_name(id: String) -> String:
	for m in ModManager.list_mods():
		if str(m.id) == id:
			return str(m.name)
	return id


func _find_mod(id: String) -> Dictionary:
	for m in _last_mods:
		if str(m.id) == id:
			return m
	return {}


func _update_detail() -> void:
	var m := _find_mod(_selected_id)
	var has_mod := not m.is_empty()
	empty_label.visible = not has_mod
	detail_head.visible = has_mod
	detail_scroll.visible = has_mod
	detail_buttons.visible = has_mod
	detail_error.visible = false
	if not has_mod:
		return
	var name := str(m.get("name", _selected_id))
	detail_name.text = name
	var meta: Array = []
	var version := str(m.get("version", ""))
	var author := str(m.get("author", ""))
	if version != "":
		meta.append("v" + version)
	if author != "":
		meta.append(author)
	if _is_pending(_selected_id):
		meta.append(tr("mod_detail_pending"))
	detail_meta.text = _join_values(meta, "  ")
	detail_meta.visible = not meta.is_empty()

	var tex := _load_icon(str(m.get("icon", "")))
	detail_icon.texture = tex
	detail_icon.visible = tex != null
	detail_initial.visible = tex == null
	detail_initial.text = _name_initial(name, _selected_id)

	var err := str(m.get("error", ""))
	detail_error.text = tr("mod_tag_error") % err
	detail_error.visible = err != ""

	var desc := str(m.get("description", ""))
	detail_desc.text = desc
	detail_desc.visible = desc != ""

	detail_deps.text = tr("mod_detail_dependencies") % _join_or_none(Array(m.get("dependencies", [])))
	detail_adds.text = tr("mod_detail_adds") % _content_summary(m.get("adds", {}))

	var scripts: Array = []
	for p in Array(m.get("replace_paths", [])):
		scripts.append(str(p).get_file())
	detail_override_scripts.text = tr("mod_detail_override_scripts") % _join_or_none(scripts)
	detail_override_scripts.visible = not scripts.is_empty()

	var overrides := Array(m.get("overrides", []))
	detail_overrides.text = tr("mod_detail_overrides") % _join_or_none(overrides)
	detail_overrides.visible = not overrides.is_empty()

	var required := str(m.get("game_version", ""))
	detail_min_version.text = tr("mod_detail_min_game_version") % (required if required != "" else tr("mod_detail_undeclared"))
	var current := str(Game.version_number) if is_instance_valid(Game) else ""
	if required == "" or current == "":
		detail_min_state.visible = false
	elif bool(m.get("game_version_ok", true)):
		detail_min_state.text = tr("mod_detail_min_met") % current
		detail_min_state.add_theme_color_override("font_color", OK_COLOR)
		detail_min_state.visible = true
	else:
		detail_min_state.text = tr("mod_detail_min_unmet") % current
		detail_min_state.add_theme_color_override("font_color", DANGER)
		detail_min_state.visible = true

	detail_dir.text = tr("mod_detail_dir") % str(m.get("dir", ""))


func _name_initial(name: String, id: String) -> String:
	var text := name.strip_edges()
	if text == "":
		text = id.strip_edges()
	if text == "":
		return "?"
	var skip := [" ", "　", "\t", "\n", "·", "-", "_", ".", ":", "[", "]", "(", ")", "（", "）", "【", "】", "/", "\\"]
	for i in text.length():
		var ch := text.substr(i, 1)
		if skip.has(ch):
			continue
		return ch.to_upper()
	return "?"


func _join_or_none(values: Array) -> String:
	if values.is_empty():
		return tr("mod_detail_none")
	return _join_values(values, " · ")


func _join_values(values: Array, separator: String) -> String:
	var parts := PackedStringArray()
	for v in values:
		parts.append(str(v))
	return separator.join(parts)


func _content_summary(adds) -> String:
	if not (adds is Dictionary) or adds.is_empty():
		return tr("mod_detail_none")
	var parts: Array = []
	for kind in ["characters", "societies", "upgrades", "enemies", "supports", "clothes", "shop_characters", "game_modes", "levels"]:
		if adds.has(kind):
			parts.append("%s %d" % [tr("mod_kind_" + str(kind)), int(adds[kind])])
	return _join_values(parts, " · ") if not parts.is_empty() else tr("mod_detail_none")
