class_name DanmakuFieldInspector
extends VBoxContainer

## 通用字段检查器：按 Object 的编辑器属性自动生成控件。
## 只用于弹幕编辑器（开发工具），支持 bool/int/float/String/StringName/Color/Vector2/枚举/PackedScene。
## 新增 DanmakuPattern 字段时无需改这里，除非类型不在支持列表内。

signal value_changed(property: String, value: Variant)

const LABELS := {
	"id": "标识",
	"display_name": "显示名",
	"notes": "备注",
	"bullet_scene": "弹体场景",
	"spread": "散布方式",
	"count": "发数",
	"arc_deg": "扇形角度",
	"parallel_spacing": "平行间距",
	"aim": "朝向",
	"fixed_angle_deg": "固定角",
	"angle_offset_deg": "角度偏移",
	"spin_per_volley_deg": "每波旋转",
	"muzzle_offset": "枪口偏移",
	"speed": "速度",
	"speed_random": "速度抖动",
	"accel": "加速度",
	"curvature_deg_per_sec": "弧线(°/秒)",
	"homing_deg_per_sec": "追踪转向(°/秒)",
	"homing_duration": "追踪时长",
	"lifetime": "存活(秒)",
	"scale_mult": "缩放",
	"penetrate": "穿透",
	"damage_mult": "伤害倍率",
	"knockback_mult": "击退倍率",
	"split_count": "分裂数",
	"sfx": "音效名",
	"muzzle_fx": "枪口特效",
	"volley_count": "连射波数",
	"volley_interval": "连射间隔",
}

var _target: Object = null
var _updating: bool = false
var _file_dialog: FileDialog = null
var _pending_property: String = ""
var _object_buttons: Dictionary = {}


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 2)


func bind(target: Object) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_object_buttons.clear()
	_target = target
	if target == null:
		return
	var infos := _property_map(target)
	for name in _ordered_names(infos):
		_add_row(name, infos[name])


func _property_map(target: Object) -> Dictionary:
	var out := {}
	for info in target.get_property_list():
		var name := String(info.get("name", ""))
		if name == "" or name.begins_with("_") or name.begins_with("resource_"):
			continue
		var usage: int = int(info.get("usage", 0))
		if (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		out[name] = info
	return out


func _ordered_names(infos: Dictionary) -> Array[String]:
	var out: Array[String] = []
	# 先按 LABELS 的书写顺序，再补漏。
	for name in LABELS.keys():
		if infos.has(name):
			out.append(name)
	for name in infos.keys():
		if not out.has(name):
			out.append(name)
	return out


func _add_row(property: String, info: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = String(LABELS.get(property, property))
	label.tooltip_text = property
	label.add_theme_font_size_override("font_size", 8)
	label.custom_minimum_size = Vector2(78.0, 0.0)
	label.clip_text = true
	row.add_child(label)
	row.add_child(_make_editor(property, info))
	add_child(row)


func _make_editor(property: String, info: Dictionary) -> Control:
	var value = _target.get(property)
	var type: int = int(info.get("type", TYPE_NIL))
	var hint: int = int(info.get("hint", PROPERTY_HINT_NONE))
	var hint_string := String(info.get("hint_string", ""))

	match type:
		TYPE_BOOL:
			var check := CheckButton.new()
			check.button_pressed = bool(value)
			check.text = "开" if bool(value) else "关"
			check.add_theme_font_size_override("font_size", 9)
			check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			check.toggled.connect(func(pressed: bool) -> void:
				check.text = "开" if pressed else "关"
				_apply(property, pressed)
			)
			return check
		TYPE_INT:
			if hint == PROPERTY_HINT_ENUM:
				return _make_enum(property, hint_string, int(value))
			return _make_spin(property, float(value), 1.0, _range_of(info, 1.0), true)
		TYPE_FLOAT:
			return _make_spin(property, float(value), _range_of(info, 0.05).z, _range_of(info, 0.05), false)
		TYPE_STRING, TYPE_STRING_NAME:
			var edit := LineEdit.new()
			edit.text = String(value) if value != null else ""
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.custom_minimum_size = Vector2(0.0, 18.0)
			edit.add_theme_font_size_override("font_size", 8)
			edit.text_changed.connect(func(text: String) -> void: _apply(property, text))
			return edit
		TYPE_VECTOR2:
			var box := HBoxContainer.new()
			box.add_theme_constant_override("separation", 2)
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var vector := Vector2.ZERO
			if value is Vector2:
				vector = value
			var spin_x := _make_spin(property + ".x", vector.x, 1.0, Vector3(-4096, 4096, 1), false)
			var spin_y := _make_spin(property + ".y", vector.y, 1.0, Vector3(-4096, 4096, 1), false)
			box.add_child(spin_x)
			box.add_child(spin_y)
			return box
		TYPE_OBJECT:
			return _make_object_editor(property, value)
		TYPE_COLOR:
			var color_edit := ColorPickerButton.new()
			if value is Color:
				color_edit.color = value
			color_edit.custom_minimum_size = Vector2(0.0, 20.0)
			color_edit.edit_alpha = true
			color_edit.color_changed.connect(func(color: Color) -> void: _apply(property, color))
			return color_edit
		_:
			var label := Label.new()
			label.text = str(value)
			label.add_theme_font_size_override("font_size", 9)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			return label


func _make_enum(property: String, hint_string: String, current: int) -> OptionButton:
	var option := OptionButton.new()
	option.add_theme_font_size_override("font_size", 9)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var names := hint_string.split(",")
	for i in names.size():
		option.add_item(String(names[i]).strip_edges(), i)
	option.select(clampi(current, 0, maxi(0, names.size() - 1)))
	option.item_selected.connect(func(index: int) -> void: _apply(property, index))
	return option


func _make_spin(
	property: String, current: float, default_step: float, range_value: Vector3, is_int: bool
) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = range_value.x
	spin.max_value = range_value.y
	spin.step = default_step if range_value.z <= 0.0 else range_value.z
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.custom_minimum_size = Vector2(54.0, 18.0)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.get_line_edit().add_theme_font_size_override("font_size", 8)
	_updating = true
	spin.value = current
	_updating = false
	if property.ends_with(".x") or property.ends_with(".y"):
		var base := property.substr(0, property.length() - 2)
		var axis := property.substr(property.length() - 1, 1)
		spin.value_changed.connect(func(value: float) -> void: _apply_vector_axis(base, axis, value))
	else:
		spin.value_changed.connect(func(value: float) -> void:
			_apply(property, int(round(value)) if is_int else value)
		)
	return spin


func _apply_vector_axis(base: String, axis: String, value: float) -> void:
	if _target == null or _updating:
		return
	var vector := Vector2.ZERO
	if _target.get(base) is Vector2:
		vector = _target.get(base)
	if axis == "x":
		vector.x = value
	else:
		vector.y = value
	_apply(base, vector)


func _make_object_editor(property: String, value: Variant) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var button := Button.new()
	button.add_theme_font_size_override("font_size", 9)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text = _resource_label(value)
	button.pressed.connect(func() -> void: _open_file_dialog(property))
	row.add_child(button)
	_object_buttons[property] = button
	var clear := Button.new()
	clear.text = "×"
	clear.add_theme_font_size_override("font_size", 9)
	clear.tooltip_text = "清空"
	clear.pressed.connect(func() -> void: _apply(property, null))
	row.add_child(clear)
	return row


func _resource_label(value: Variant) -> String:
	if value == null:
		return "（空）"
	if value is Resource:
		var path := (value as Resource).resource_path
		if path != "":
			return path.get_file()
		return (value as Resource).get_class()
	return str(value)


func _open_file_dialog(property: String) -> void:
	_pending_property = property
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.access = FileDialog.ACCESS_RESOURCES
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.use_native_dialog = false
		_file_dialog.filters = PackedStringArray(["*.tscn ; 场景", "*.tres ; 资源", "* ; 全部"])
		_file_dialog.size = Vector2i(720, 480)
		_file_dialog.file_selected.connect(_on_file_selected)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.6)


func _on_file_selected(path: String) -> void:
	if _pending_property == "":
		return
	var resource := load(path)
	if resource == null:
		push_warning("[DanmakuInspector] 加载失败：%s" % path)
		return
	_apply(_pending_property, resource)
	_pending_property = ""


func _apply(property: String, value: Variant) -> void:
	if _target == null or _updating:
		return
	_target.set(property, value)
	if _object_buttons.has(property):
		var button: Button = _object_buttons[property]
		if button != null and is_instance_valid(button):
			button.text = _resource_label(value)
	value_changed.emit(property, value)


func _range_of(info: Dictionary, default_step: float) -> Vector3:
	if int(info.get("hint", 0)) == PROPERTY_HINT_RANGE:
		var parts := String(info.get("hint_string", "")).split(",")
		if parts.size() >= 2:
			var min_value := float(parts[0])
			var max_value := float(parts[1])
			var step := float(parts[2]) if parts.size() >= 3 else default_step
			return Vector3(min_value, max_value, step)
	return Vector3(-99999.0, 99999.0, default_step)
