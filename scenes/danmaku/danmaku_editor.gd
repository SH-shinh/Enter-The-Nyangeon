extends Node2D

## 弹幕编辑器（游戏内工具场景，F6 运行）。
## 左栏：招式组 / 招式 / 条目 / 图案字段；底部：时间轴；中间：预览场（可拖发射器与目标标记）。
## 保存目标：resources/danmaku/{patterns,barrages,sets}。仅编辑器内可写 res://。

const PATTERN_DIR := "res://resources/danmaku/patterns"
const BARRAGE_DIR := "res://resources/danmaku/barrages"
const SET_DIR := "res://resources/danmaku/sets"
const DEMO_SET := "res://resources/danmaku/sets/demo_set.tres"
const DEFAULT_BULLET := "res://scenes/bullet/enemy_bullet.tscn"

const LEFT_WIDTH := 230.0
const TIMELINE_HEIGHT := 118.0

@onready var _preview: DanmakuPreview = $Preview
@onready var _camera: Camera2D = $Preview/Camera2D

var _ui: CanvasLayer
var _status: Label
var _sim_status: Label
var _title: Label

var _set: DanmakuSet = null
var _barrage: DanmakuBarrage = null
var _pattern: DanmakuPattern = null
var _cue_index: int = -1
var _set_path: String = ""
var _barrage_path: String = ""

var _set_files: Array[String] = []
var _pattern_paths: Array[String] = []
var _pattern_cache: Dictionary = {}
var _dragging_marker: int = 0

var _syncing: bool = false
var _playing_single: bool = false

# set widgets
var _set_select: OptionButton
var _set_id: LineEdit
var _loop_check: CheckButton
var _budget_spin: SpinBox
var _rest_spin: SpinBox
var _threshold_edit: LineEdit
var _seed_spin: SpinBox
# barrage widgets
var _barrage_list: ItemList
var _barrage_id: LineEdit
var _barrage_duration: SpinBox
var _barrage_cooldown: SpinBox
var _barrage_intro: SpinBox
var _barrage_weight: SpinBox
var _phase_checks: Array[CheckBox] = []
var _anim_edit: LineEdit
# cue widgets
var _cue_time: SpinBox
var _cue_repeat: SpinBox
var _cue_interval: SpinBox
var _cue_offset: SpinBox
var _cue_pattern: OptionButton
# pattern widgets
var _pattern_list: ItemList
var _pattern_info: Label
var _inspector: DanmakuFieldInspector
var _timeline: DanmakuTimeline


func _ready() -> void:
	_camera.offset = Vector2(-LEFT_WIDTH * 0.5, TIMELINE_HEIGHT * 0.5)
	_build_ui()
	_refresh_pattern_list()
	_refresh_set_list()
	_load_demo_set()
	_set_status("拖动世界里的红圈=发射器、蓝菱=目标；右键时间轴方块=删除；Space=播放/暂停。")


# ---------------- UI 构建 ----------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	add_child(_ui)

	var left := PanelContainer.new()
	left.name = "LeftPanel"
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_right = LEFT_WIDTH
	_ui.add_child(left)

	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 2)
	left.add_child(left_box)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 3)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content)

	_title = _label("弹幕编辑器", 11)
	_title.clip_text = true
	_title.custom_minimum_size = Vector2(0.0, 14.0)
	content.add_child(_title)

	_build_set_section(content)
	_build_barrage_section(content)
	_build_cue_section(content)
	_build_pattern_section(content)

	_status = _label("", 8)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0.0, 34.0)
	left_box.add_child(_status)
	var bottom := PanelContainer.new()
	bottom.name = "TimelinePanel"
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = LEFT_WIDTH
	bottom.offset_top = -TIMELINE_HEIGHT
	_ui.add_child(bottom)

	var bottom_box := VBoxContainer.new()
	bottom_box.add_theme_constant_override("separation", 2)
	bottom.add_child(bottom_box)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 4)
	bottom_box.add_child(toolbar)
	toolbar.add_child(_button("▶ 当前招", _play_current_barrage))
	toolbar.add_child(_button("▶ 整组", _play_set))
	toolbar.add_child(_button("■ 停止", _stop_preview))
	toolbar.add_child(_button("清弹", _clear_bullets))
	toolbar.add_child(_button("+ 条目", _add_cue_at_playhead))
	_sim_status = _label("", 9)
	_sim_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_sim_status)

	_timeline = DanmakuTimeline.new()
	_timeline.name = "Timeline"
	_timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.cue_selected.connect(_on_timeline_cue_selected)
	_timeline.cue_time_changed.connect(_on_timeline_cue_time_changed)
	_timeline.cue_delete_requested.connect(_on_timeline_cue_delete)
	_timeline.seek.connect(_on_timeline_seek)
	bottom_box.add_child(_timeline)


func _build_set_section(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("招式组 (Set)"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	_set_select = OptionButton.new()
	_set_select.add_theme_font_size_override("font_size", 9)
	_set_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_set_select)
	row.add_child(_button("载入", _load_selected_set))
	parent.add_child(row)

	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 3)
	id_row.add_child(_small_label("id"))
	_set_id = _line_edit()
	_set_id.text_changed.connect(func(text: String) -> void:
		if not _syncing and _set != null:
			_set.id = text
			_update_title()
	)
	id_row.add_child(_set_id)
	parent.add_child(id_row)

	_loop_check = CheckButton.new()
	_loop_check.text = "无限轮转"
	_loop_check.add_theme_font_size_override("font_size", 9)
	_loop_check.toggled.connect(func(pressed: bool) -> void:
		if not _syncing and _set != null:
			_set.loop = pressed
	)
	parent.add_child(_loop_check)

	var num_row := HBoxContainer.new()
	num_row.add_theme_constant_override("separation", 3)
	num_row.add_child(_small_label("预算"))
	_budget_spin = _spin(8, 200, 1, 120)
	_budget_spin.value_changed.connect(func(value: float) -> void:
		if not _syncing and _set != null:
			_set.max_active_bullets = int(round(value))
	)
	num_row.add_child(_budget_spin)
	num_row.add_child(_small_label("休息"))
	_rest_spin = _spin(0, 30, 0.05, 0)
	_rest_spin.value_changed.connect(func(value: float) -> void:
		if not _syncing and _set != null:
			_set.rest_between_barrages = value
	)
	num_row.add_child(_rest_spin)
	parent.add_child(num_row)

	var phase_row := HBoxContainer.new()
	phase_row.add_theme_constant_override("separation", 3)
	phase_row.add_child(_small_label("血量阈值"))
	_threshold_edit = _line_edit()
	_threshold_edit.placeholder_text = "0.5,0.25"
	_threshold_edit.tooltip_text = "逗号分隔、降序；ratio 严格小于阈值进入下一阶段"
	_threshold_edit.text_submitted.connect(func(_text: String) -> void: _commit_thresholds())
	_threshold_edit.focus_exited.connect(_commit_thresholds)
	phase_row.add_child(_threshold_edit)
	parent.add_child(phase_row)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 3)
	seed_row.add_child(_small_label("随机种子"))
	_seed_spin = _spin(0, 999999999, 1, 0)
	_seed_spin.value_changed.connect(func(value: float) -> void:
		if not _syncing and _set != null:
			_set.rng_seed = int(round(value))
	)
	seed_row.add_child(_seed_spin)
	seed_row.add_child(_button("保存招式组", _save_set))
	parent.add_child(seed_row)


func _build_barrage_section(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("招式 (Barrage)"))
	_barrage_list = ItemList.new()
	_barrage_list.custom_minimum_size = Vector2(0.0, 62.0)
	_barrage_list.add_theme_font_size_override("font_size", 9)
	_barrage_list.item_selected.connect(func(index: int) -> void: _select_barrage(index))
	parent.add_child(_barrage_list)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 2)
	buttons.add_child(_button("新建", _new_barrage))
	buttons.add_child(_button("复制", _duplicate_barrage))
	buttons.add_child(_button("删除", _delete_barrage))
	buttons.add_child(_button("保存招式", _save_barrage))
	parent.add_child(buttons)

	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 3)
	id_row.add_child(_small_label("id"))
	_barrage_id = _line_edit()
	_barrage_id.text_changed.connect(func(text: String) -> void:
		if not _syncing:
			_apply_barrage_meta()
	)
	_barrage_id.text = ""
	id_row.add_child(_barrage_id)
	parent.add_child(id_row)

	var num_row := HBoxContainer.new()
	num_row.add_theme_constant_override("separation", 3)
	num_row.add_child(_small_label("时长"))
	_barrage_duration = _spin(0, 30, 0.05, 2.0)
	_barrage_duration.value_changed.connect(func(_v: float) -> void: _apply_barrage_meta())
	num_row.add_child(_barrage_duration)
	num_row.add_child(_small_label("冷却"))
	_barrage_cooldown = _spin(0, 30, 0.05, 1.0)
	_barrage_cooldown.value_changed.connect(func(_v: float) -> void: _apply_barrage_meta())
	num_row.add_child(_barrage_cooldown)
	parent.add_child(num_row)

	var num_row2 := HBoxContainer.new()
	num_row2.add_theme_constant_override("separation", 3)
	num_row2.add_child(_small_label("前摇"))
	_barrage_intro = _spin(0, 10, 0.05, 0)
	_barrage_intro.value_changed.connect(func(_v: float) -> void: _apply_barrage_meta())
	num_row2.add_child(_barrage_intro)
	num_row2.add_child(_small_label("权重"))
	_barrage_weight = _spin(0, 100, 0.5, 1.0)
	_barrage_weight.value_changed.connect(func(_v: float) -> void: _apply_barrage_meta())
	num_row2.add_child(_barrage_weight)
	parent.add_child(num_row2)

	var phase_row := HBoxContainer.new()
	phase_row.add_theme_constant_override("separation", 2)
	phase_row.add_child(_small_label("阶段"))
	for i in 4:
		var check := CheckBox.new()
		check.text = "P%d" % (i + 1)
		check.add_theme_font_size_override("font_size", 9)
		check.toggled.connect(func(_pressed: bool) -> void: _apply_barrage_meta())
		phase_row.add_child(check)
		_phase_checks.append(check)
	parent.add_child(phase_row)

	var anim_row := HBoxContainer.new()
	anim_row.add_theme_constant_override("separation", 3)
	anim_row.add_child(_small_label("动画名"))
	_anim_edit = _line_edit()
	_anim_edit.text_changed.connect(func(_text: String) -> void: _apply_barrage_meta())
	anim_row.add_child(_anim_edit)
	parent.add_child(anim_row)


func _build_cue_section(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("时间轴条目 (Cue)"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.add_child(_small_label("时间"))
	_cue_time = _spin(0, 60, 0.05, 0)
	_cue_time.value_changed.connect(func(value: float) -> void: _apply_selected_cue_time(value))
	row.add_child(_cue_time)
	row.add_child(_small_label("重复"))
	_cue_repeat = _spin(1, 64, 1, 1)
	_cue_repeat.value_changed.connect(func(_v: float) -> void: _apply_cue_fields())
	row.add_child(_cue_repeat)
	parent.add_child(row)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 3)
	row2.add_child(_small_label("间隔"))
	_cue_interval = _spin(0.05, 10, 0.05, 0.5)
	_cue_interval.value_changed.connect(func(_v: float) -> void: _apply_cue_fields())
	row2.add_child(_cue_interval)
	row2.add_child(_small_label("偏角"))
	_cue_offset = _spin(-360, 360, 1, 0)
	_cue_offset.value_changed.connect(func(_v: float) -> void: _apply_cue_fields())
	row2.add_child(_cue_offset)
	parent.add_child(row2)

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 3)
	row3.add_child(_small_label("图案"))
	_cue_pattern = OptionButton.new()
	_cue_pattern.add_theme_font_size_override("font_size", 9)
	_cue_pattern.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cue_pattern.item_selected.connect(_on_cue_pattern_selected)
	row3.add_child(_cue_pattern)
	parent.add_child(row3)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 2)
	buttons.add_child(_button("在游标添加", _add_cue_at_playhead))
	buttons.add_child(_button("删除条目", _delete_selected_cue))
	parent.add_child(buttons)


func _build_pattern_section(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("图案 (Pattern)"))
	_pattern_list = ItemList.new()
	_pattern_list.custom_minimum_size = Vector2(0.0, 62.0)
	_pattern_list.add_theme_font_size_override("font_size", 9)
	_pattern_list.item_selected.connect(_on_pattern_selected)
	_pattern_list.item_activated.connect(_on_pattern_selected)
	parent.add_child(_pattern_list)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 2)
	buttons.add_child(_button("新建", _new_pattern))
	buttons.add_child(_button("复制", _duplicate_pattern))
	buttons.add_child(_button("保存图案", _save_pattern))
	parent.add_child(buttons)

	_pattern_info = _label("（未选择图案）", 8)
	_pattern_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pattern_info.custom_minimum_size = Vector2(0.0, 18.0)
	parent.add_child(_pattern_info)

	_inspector = DanmakuFieldInspector.new()
	_inspector.name = "PatternInspector"
	_inspector.value_changed.connect(_on_pattern_value_changed)
	parent.add_child(_inspector)


# ---------------- 小工具 ----------------

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	return label


func _small_label(text: String) -> Label:
	var label := _label(text, 8)
	label.custom_minimum_size = Vector2(34.0, 0.0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.clip_text = true
	return label


func _section_label(text: String) -> Label:
	var label := _label(text, 10)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	return label


func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 8)
	button.pressed.connect(callback)
	return button


func _line_edit() -> LineEdit:
	var edit := LineEdit.new()
	edit.add_theme_font_size_override("font_size", 8)
	edit.custom_minimum_size = Vector2(0.0, 18.0)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return edit


func _spin(min_value: float, max_value: float, step: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.custom_minimum_size = Vector2(50.0, 18.0)
	spin.get_line_edit().add_theme_font_size_override("font_size", 8)
	spin.value = value
	return spin


func _set_spin(spin: SpinBox, value: float) -> void:
	_syncing = true
	spin.value = value
	_syncing = false


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _update_title() -> void:
	if _title == null:
		return
	var set_name := _set.id if _set != null else "?"
	var barrage_name := _barrage.id if _barrage != null else "?"
	_title.text = "弹幕编辑器　[%s / %s]" % [set_name, barrage_name]


# ---------------- 招式组 ----------------

func _refresh_set_list() -> void:
	_set_files.clear()
	_set_select.clear()
	for path in _scan(SET_DIR, ".tres"):
		_set_files.append(path)
		_set_select.add_item(path.get_file().get_basename())
	if _set_files.is_empty():
		_set_select.add_item("（无招式组）")


func _load_demo_set() -> void:
	var resource: Resource = ResourceLoader.load(DEMO_SET) if FileAccess.file_exists(DEMO_SET) else null
	if resource is DanmakuSet:
		_apply_set(resource, DEMO_SET)
	else:
		var fresh := DanmakuSet.new()
		fresh.id = "new_set"
		_apply_set(fresh, "")


func _load_selected_set() -> void:
	var index := _set_select.selected
	if index < 0 or index >= _set_files.size():
		_set_status("请选择一个招式组文件")
		return
	_apply_set(ResourceLoader.load(_set_files[index]), _set_files[index])


func _apply_set(value: DanmakuSet, path: String) -> void:
	_set = value
	_set_path = path
	_syncing = true
	_set_id.text = _set.id
	var set_index := _set_files.find(path)
	if set_index >= 0:
		_set_select.select(set_index)
	_loop_check.set_pressed_no_signal(_set.loop)
	_budget_spin.value = _set.max_active_bullets
	_rest_spin.value = _set.rest_between_barrages
	_seed_spin.value = _set.rng_seed
	_threshold_edit.text = _thresholds_text(_set.phase_hp_thresholds)
	_syncing = false
	_preview.setup(_set)
	_refresh_barrage_list()
	if not _set.barrages.is_empty():
		_select_barrage(0)
	else:
		_barrage = null
		_refresh_cue_pattern_options()
		_timeline.set_barrage(null)
	_update_title()


func _thresholds_text(values: PackedFloat32Array) -> String:
	var parts: Array[String] = []
	for value in values:
		parts.append(str(value))
	return ",".join(parts)


func _commit_thresholds() -> void:
	if _syncing or _set == null:
		return
	var values := PackedFloat32Array()
	for part in _threshold_edit.text.split(","):
		var text := part.strip_edges()
		if text == "":
			continue
		values.append(float(text))
	_set.phase_hp_thresholds = values


func _save_set() -> void:
	if not _ensure_editor():
		return
	if _set == null:
		return
	var base := _sanitize(_set.id if _set.id != "" else "new_set")
	_set.id = base
	_ensure_dir(SET_DIR)
	var path := SET_DIR.path_join(base + ".tres")
	var err := ResourceSaver.save(_set, path)
	if err == OK:
		_set_path = path
		_refresh_set_list()
		var warnings := _set.validate()
		if warnings.is_empty():
			_set_status("已保存招式组：%s" % path)
		else:
			_set_status("已保存，但有 %d 条校验警告：%s" % [warnings.size(), warnings[0]])
	else:
		_set_status("保存招式组失败：error %d" % err)


# ---------------- 招式 ----------------

func _refresh_barrage_list() -> void:
	_barrage_list.clear()
	if _set == null:
		return
	for i in _set.barrages.size():
		var barrage := _set.barrages[i]
		var text := "%d. %s" % [i + 1, barrage.barrage_label() if barrage != null else "（空）"]
		_barrage_list.add_item(text)
	if _barrage != null:
		var index := _set.barrages.find(_barrage)
		if index >= 0:
			_barrage_list.select(index)


func _select_barrage(index: int) -> void:
	if _set == null or index < 0 or index >= _set.barrages.size():
		return
	_barrage = _set.barrages[index]
	_barrage_path = _barrage.resource_path
	_cue_index = -1
	_syncing = true
	_barrage_id.text = _barrage.id
	_barrage_duration.value = _barrage.duration
	_barrage_cooldown.value = _barrage.cooldown
	_barrage_intro.value = _barrage.intro_delay
	_barrage_weight.value = _barrage.weight
	_anim_edit.text = String(_barrage.anim_name)
	for i in _phase_checks.size():
		_phase_checks[i].set_pressed_no_signal((_barrage.phases & (1 << i)) != 0)
	_syncing = false
	_timeline.set_barrage(_barrage)
	_preview.setup(_set)
	_refresh_cue_pattern_options()
	_bind_cue(-1)
	_update_title()


func _apply_barrage_meta() -> void:
	if _syncing or _barrage == null:
		return
	_barrage.id = _barrage_id.text.strip_edges()
	_barrage.duration = _barrage_duration.value
	_barrage.cooldown = _barrage_cooldown.value
	_barrage.intro_delay = _barrage_intro.value
	_barrage.weight = _barrage_weight.value
	_barrage.anim_name = StringName(_anim_edit.text.strip_edges())
	var phases := 0
	for i in _phase_checks.size():
		if _phase_checks[i].button_pressed:
			phases |= 1 << i
	_barrage.phases = phases
	_refresh_barrage_list()
	_timeline.refresh()
	_update_title()


func _new_barrage() -> void:
	if _set == null:
		return
	var barrage := DanmakuBarrage.new()
	barrage.id = "barrage_%d" % (_set.barrages.size() + 1)
	barrage.display_name = barrage.id
	_set.barrages.append(barrage)
	_refresh_barrage_list()
	_select_barrage(_set.barrages.size() - 1)
	_set_status("已新建招式 %s（记得保存）" % barrage.id)


func _duplicate_barrage() -> void:
	if _set == null or _barrage == null:
		return
	var copy: DanmakuBarrage = _barrage.duplicate(true)
	copy.id = _barrage.id + "_copy"
	copy.resource_path = ""
	_set.barrages.append(copy)
	_refresh_barrage_list()
	_select_barrage(_set.barrages.size() - 1)


func _delete_barrage() -> void:
	if _set == null or _barrage == null:
		return
	var index := _set.barrages.find(_barrage)
	if index >= 0:
		_set.barrages.remove_at(index)
	_barrage = null
	_barrage_path = ""
	if not _set.barrages.is_empty():
		_select_barrage(clampi(index, 0, _set.barrages.size() - 1))
	else:
		_refresh_barrage_list()
		_timeline.set_barrage(null)
		_update_title()


func _save_barrage() -> void:
	if not _ensure_editor():
		return
	if _barrage == null:
		return
	var base := _sanitize(_barrage.id if _barrage.id != "" else "barrage")
	_barrage.id = base
	_ensure_dir(BARRAGE_DIR)
	var path := _barrage_path
	if path == "" or not path.begins_with(BARRAGE_DIR):
		path = BARRAGE_DIR.path_join(base + ".tres")
	var err := ResourceSaver.save(_barrage, path)
	if err == OK:
		_barrage_path = path
		_set_status("已保存招式：%s" % path)
	else:
		_set_status("保存招式失败：error %d" % err)


# ---------------- 条目 ----------------

func _refresh_cue_pattern_options() -> void:
	_cue_pattern.clear()
	for i in _pattern_paths.size():
		_cue_pattern.add_item(_pattern_paths[i].get_file().get_basename(), i)
	if _barrage != null and _cue_index >= 0 and _cue_index < _barrage.cues.size():
		var cue := _barrage.cues[_cue_index]
		if cue != null and cue.pattern != null and cue.pattern.resource_path != "":
			var index := _pattern_paths.find(cue.pattern.resource_path)
			if index >= 0:
				_cue_pattern.select(index)


func _bind_cue(index: int) -> void:
	_cue_index = index
	var cue: DanmakuCue = null
	if _barrage != null and index >= 0 and index < _barrage.cues.size():
		cue = _barrage.cues[index]
	_syncing = true
	if cue == null:
		_cue_time.value = _timeline.playhead if _timeline != null else 0.0
		_cue_repeat.value = 1
		_cue_interval.value = 0.5
		_cue_offset.value = 0.0
	else:
		_cue_time.value = cue.time
		_cue_repeat.value = cue.repeat
		_cue_interval.value = cue.repeat_interval
		_cue_offset.value = cue.angle_offset_deg
		if cue.pattern != null and cue.pattern.resource_path != "":
			var pattern_index := _pattern_paths.find(cue.pattern.resource_path)
			if pattern_index >= 0:
				_cue_pattern.select(pattern_index)
	_syncing = false
	_timeline.set_selected(index)


func _apply_selected_cue_time(value: float) -> void:
	if _syncing or _barrage == null or _cue_index < 0 or _cue_index >= _barrage.cues.size():
		return
	_barrage.cues[_cue_index].time = value
	_timeline.refresh()


func _apply_cue_fields() -> void:
	if _syncing or _barrage == null or _cue_index < 0 or _cue_index >= _barrage.cues.size():
		return
	var cue := _barrage.cues[_cue_index]
	if cue == null:
		return
	cue.repeat = maxi(1, int(round(_cue_repeat.value)))
	cue.repeat_interval = _cue_interval.value
	cue.angle_offset_deg = _cue_offset.value
	_timeline.refresh()


func _on_cue_pattern_selected(index: int) -> void:
	if _syncing or _barrage == null or _cue_index < 0 or _cue_index >= _barrage.cues.size():
		return
	if index < 0 or index >= _pattern_paths.size():
		return
	var pattern := _load_pattern(_pattern_paths[index])
	if pattern == null:
		return
	_barrage.cues[_cue_index].pattern = pattern
	_refresh_barrage_list()
	_timeline.refresh()


func _add_cue_at_playhead() -> void:
	if _barrage == null:
		_set_status("先选择或新建一个招式")
		return
	if _pattern == null:
		_set_status("先在图案列表里选择一个图案")
		return
	var cue := DanmakuCue.new()
	cue.pattern = _pattern
	cue.time = snappedf(_timeline.playhead, 0.05)
	_barrage.cues.append(cue)
	_cue_index = _barrage.cues.size() - 1
	var head := _timeline.playhead
	_timeline.set_barrage(_barrage)
	_timeline.set_playhead(head)
	_bind_cue(_cue_index)
	_set_status("已在 %.2fs 添加 %s" % [cue.time, _pattern.label()])


func _delete_selected_cue() -> void:
	if _barrage == null or _cue_index < 0 or _cue_index >= _barrage.cues.size():
		return
	_barrage.cues.remove_at(_cue_index)
	_cue_index = -1
	_timeline.set_barrage(_barrage)
	_bind_cue(-1)
	_refresh_barrage_list()


func _on_timeline_cue_selected(index: int) -> void:
	_bind_cue(index)


func _on_timeline_cue_time_changed(index: int, time: float) -> void:
	if _barrage == null or index < 0 or index >= _barrage.cues.size():
		return
	_barrage.cues[index].time = time
	_timeline.refresh()
	if index == _cue_index:
		_syncing = true
		_cue_time.value = time
		_syncing = false


func _on_timeline_cue_delete(index: int) -> void:
	if _barrage == null or index < 0 or index >= _barrage.cues.size():
		return
	_barrage.cues.remove_at(index)
	_cue_index = -1
	_timeline.set_barrage(_barrage)
	_timeline.set_selected(-1)
	_bind_cue(-1)
	_refresh_barrage_list()


func _on_timeline_seek(time: float) -> void:
	if _cue_index < 0:
		_syncing = true
		_cue_time.value = time
		_syncing = false


# ---------------- 图案 ----------------

func _refresh_pattern_list() -> void:
	_pattern_paths.clear()
	_pattern_cache.clear()
	_pattern_list.clear()
	for path in _scan(PATTERN_DIR, ".tres"):
		_pattern_paths.append(path)
		_pattern_list.add_item(path.get_file().get_basename())
	_refresh_cue_pattern_options()


func _load_pattern(path: String) -> DanmakuPattern:
	if _pattern_cache.has(path) and _pattern_cache[path] != null:
		return _pattern_cache[path]
	var resource := ResourceLoader.load(path)
	if resource is DanmakuPattern:
		_pattern_cache[path] = resource
		return resource
	return null


func _on_pattern_selected(index: int) -> void:
	if index < 0 or index >= _pattern_paths.size():
		return
	_pattern = _load_pattern(_pattern_paths[index])
	if _pattern == null:
		return
	_pattern_info.text = "%s（%s）" % [_pattern.label(), _pattern_paths[index].get_file()]
	_inspector.bind(_pattern)


func _on_pattern_value_changed(_property: String, _value: Variant) -> void:
	_timeline.refresh()
	if _barrage != null:
		_refresh_barrage_list()


func _new_pattern() -> void:
	var pattern := DanmakuPattern.new()
	pattern.id = "pattern_%d" % (_pattern_list.item_count + 1)
	pattern.display_name = pattern.id
	pattern.bullet_scene = load(DEFAULT_BULLET)
	pattern.count = 5
	pattern.arc_deg = 60.0
	pattern.speed = 120.0
	_set_pattern_workspace(pattern, "（未保存）")


func _duplicate_pattern() -> void:
	if _pattern == null:
		return
	var copy: DanmakuPattern = _pattern.duplicate(true)
	copy.id = _pattern.id + "_copy"
	copy.display_name = copy.id
	copy.resource_path = ""
	_set_pattern_workspace(copy, "（未保存）")


func _set_pattern_workspace(pattern: DanmakuPattern, info: String) -> void:
	_pattern = pattern
	_pattern_info.text = "%s %s" % [pattern.label(), info]
	_inspector.bind(pattern)


func _save_pattern() -> void:
	if not _ensure_editor():
		return
	if _pattern == null:
		return
	var base := _sanitize(_pattern.id if _pattern.id != "" else "pattern")
	_pattern.id = base
	_ensure_dir(PATTERN_DIR)
	var path := PATTERN_DIR.path_join(base + ".tres")
	var err := ResourceSaver.save(_pattern, path)
	if err == OK:
		_pattern.resource_path = path
		_refresh_pattern_list()
		_pattern_info.text = "%s（%s）" % [_pattern.label(), path.get_file()]
		_set_status("已保存图案：%s" % path)
	else:
		_set_status("保存图案失败：error %d" % err)


# ---------------- 播放 ----------------

func _play_current_barrage() -> void:
	if _barrage == null:
		_set_status("当前没有可播放的招式")
		return
	_playing_single = true
	_preview.play_barrage(_barrage)
	_set_status("播放当前招：%s" % _barrage.barrage_label())


func _play_set() -> void:
	if _set == null:
		return
	_playing_single = false
	_preview.setup(_set)
	_preview.play_set()
	_set_status("播放整组：%s" % _set.id)


func _stop_preview() -> void:
	_preview.stop()
	_playing_single = false
	_set_status("已停止")


func _clear_bullets() -> void:
	_preview.clear_bullets()
	_set_status("已清空本发射器子弹")


func _process(delta: float) -> void:
	if _preview == null or _timeline == null:
		return
	if _preview.is_playing():
		_timeline.set_playhead(_preview.elapsed())
		var phase := _preview.get_emitter().current_phase()
		_sim_status.text = "t=%.2fs  子弹=%d  P%d" % [
			_preview.elapsed(), _preview.active_bullet_count(), phase + 1
		]
	else:
		_sim_status.text = "子弹=%d" % _preview.active_bullet_count()
	if _playing_single and not _preview.is_playing():
		_playing_single = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging_marker = _preview.hit_test_marker(get_global_mouse_position())
			else:
				_dragging_marker = 0
	elif event is InputEventMouseMotion and _dragging_marker != 0:
		var world := get_global_mouse_position()
		if _dragging_marker == 1:
			_preview.set_emitter_position(world)
		else:
			_preview.set_target_position(world)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if get_viewport().gui_get_focus_owner() is LineEdit:
			return
		if key.keycode == KEY_SPACE:
			if _preview.is_playing():
				_stop_preview()
			else:
				_play_current_barrage()
		elif key.keycode == KEY_R:
			_stop_preview()
			_play_current_barrage()
		elif key.keycode == KEY_S and key.ctrl_pressed:
			_save_all()


func _save_all() -> void:
	if _pattern != null:
		_save_pattern()
	if _barrage != null:
		_save_barrage()
	if _set != null:
		_save_set()


# ---------------- 文件 ----------------

func _ensure_editor() -> bool:
	if not OS.has_feature("editor"):
		_set_status("导出构建不能写 res://；请在 Godot 编辑器里运行本工具")
		return false
	return true


func _ensure_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))


func _sanitize(text: String) -> String:
	var base := text.strip_edges().replace(" ", "_")
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		base = base.replace(ch, "_")
	return base if base != "" else "danmaku"


func _scan(dir: String, suffix: String) -> Array[String]:
	var out: Array[String] = []
	if DirAccess.dir_exists_absolute(dir):
		for file in DirAccess.get_files_at(dir):
			if file.begins_with("_") or file.ends_with(".uid") or file.ends_with(".import"):
				continue
			if file.ends_with(suffix):
				out.append(dir.path_join(file))
	out.sort()
	return out
