extends VBoxContainer

## coop 选项内容（供「联机覆盖层 OPTION 页」与「本体 option 菜单的 COOP 页」复用）。
## UI 全部在代码中构建，避免两份 .tscn 漂移。mod 内不使用 class_name。
## 内容：其它玩家 特效/闪白/飘字 频率、调试窗口、UPnP 开关、网络自检。

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const FreqSliderScene := preload("res://ui/damage_freq_slider.tscn")
const ToggleScene := preload("res://ui/option_toggle.tscn")

var _remote_effect_slider: HSlider
var _remote_flash_slider: HSlider
var _remote_text_slider: HSlider
var _remote_effect_value: Label
var _remote_flash_value: Label
var _remote_text_value: Label
var _debug_hud_toggle = null
var _upnp_toggle = null
var _net_check_button: Button
var _net_check_result: Label


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_build()
	_refresh()
	var coop = CoopNetScript.instance
	if coop != null:
		var cb := Callable(self, "_on_netcheck_result")
		var sig = coop.get("netcheck_result")
		if sig != null and not sig.is_connected(cb):
			sig.connect(cb)


# 覆盖层打开 / 本体 option 页显示时刷新
func refresh() -> void:
	_refresh()


# 供联机覆盖层白名单使用（覆盖层会把 _panel 全部后代设 IGNORE）
func get_interactive_controls() -> Array:
	return [
		_remote_effect_slider, _remote_flash_slider, _remote_text_slider,
		_debug_hud_toggle, _upnp_toggle, _net_check_button,
	]


func _build() -> void:
	_remote_effect_slider = _add_freq_row("coop_option_remote_effect", 0)
	_remote_flash_slider = _add_freq_row("coop_option_remote_flash", 1)
	_remote_text_slider = _add_freq_row("coop_option_remote_text", 2)
	_debug_hud_toggle = _add_toggle_row("coop_option_debug_hud")
	_upnp_toggle = _add_toggle_row("coop_option_upnp")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_net_check_button = Button.new()
	_net_check_button.custom_minimum_size = Vector2(120, 30)
	_net_check_button.text = tr("coop_net_check")
	_net_check_button.pressed.connect(_on_net_check_pressed)
	_net_check_button.gui_input.connect(_on_net_check_gui_input)
	row.add_child(_net_check_button)
	_net_check_result = Label.new()
	_net_check_result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_net_check_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_check_result.add_theme_font_size_override("font_size", 9)
	_net_check_result.text = tr("coop_net_check_hint")
	row.add_child(_net_check_result)

	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 9)
	note.text = tr("coop_option_note")
	add_child(note)

	_remote_effect_slider.value_changed.connect(_on_remote_effect_value_changed)
	_remote_flash_slider.value_changed.connect(_on_remote_flash_value_changed)
	_remote_text_slider.value_changed.connect(_on_remote_text_value_changed)
	_debug_hud_toggle.toggled.connect(_on_debug_hud_toggled)
	_upnp_toggle.toggled.connect(_on_upnp_toggled)


# idx: 0=特效 1=闪白 2=飘字
func _add_freq_row(label_key: String, idx: int) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var label := Label.new()
	label.custom_minimum_size = Vector2(190, 22)
	label.add_theme_font_size_override("font_size", 12)
	label.text = tr(label_key)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var slider: HSlider = FreqSliderScene.instantiate()
	slider.custom_minimum_size = Vector2(150, 16)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var value := Label.new()
	value.custom_minimum_size = Vector2(84, 20)
	value.add_theme_font_size_override("font_size", 12)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)

	if idx == 0:
		_remote_effect_value = value
	elif idx == 1:
		_remote_flash_value = value
	else:
		_remote_text_value = value
	return slider


func _add_toggle_row(label_key: String):
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var label := Label.new()
	label.custom_minimum_size = Vector2(190, 22)
	label.add_theme_font_size_override("font_size", 12)
	label.text = tr(label_key)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var toggle = ToggleScene.instantiate()
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(toggle)
	return toggle


# ---------------- 刷新 ----------------

func _coop_settings():
	var coop = CoopNetScript.instance
	if coop == null:
		return null
	return coop.settings


func _refresh() -> void:
	var s = _coop_settings()
	var ef: int = int(s.remote_effect_freq) if s != null else 4
	var ff: int = int(s.remote_flash_freq) if s != null else 4
	var tf: int = int(s.remote_text_freq) if s != null else 4
	_remote_effect_slider.set_value_no_signal(ef)
	_remote_flash_slider.set_value_no_signal(ff)
	_remote_text_slider.set_value_no_signal(tf)
	_remote_effect_value.text = _freq_value_text(ef)
	_remote_flash_value.text = _freq_value_text(ff)
	_remote_text_value.text = _freq_value_text(tf)
	var dh: bool = bool(s.debug_hud) if s != null else false
	var hud = get_tree().get_first_node_in_group("CoopNetDebugHud")
	if hud != null and is_instance_valid(hud):
		dh = bool(hud.visible)
	_debug_hud_toggle.call("set_on", dh, false)
	var ue: bool = bool(s.upnp_enabled) if s != null else false
	_upnp_toggle.call("set_on", ue, false)


# ---------------- 频率滑条 ----------------

func _on_remote_effect_value_changed(value: float) -> void:
	var idx: int = clampi(int(round(value)), 0, 4)
	var s = _coop_settings()
	if s != null:
		s.apply_remote_effect(idx)
	_remote_effect_value.text = _freq_value_text(idx)


func _on_remote_flash_value_changed(value: float) -> void:
	var idx: int = clampi(int(round(value)), 0, 4)
	var s = _coop_settings()
	if s != null:
		s.apply_remote_flash(idx)
	_remote_flash_value.text = _freq_value_text(idx)


func _on_remote_text_value_changed(value: float) -> void:
	var idx: int = clampi(int(round(value)), 0, 4)
	var s = _coop_settings()
	if s != null:
		s.apply_remote_text(idx)
	_remote_text_value.text = _freq_value_text(idx)


func _freq_value_text(idx: int) -> String:
	match idx:
		0:
			return "0% · " + tr("damage_freq_off")
		1:
			return "25% · ×4"
		2:
			return "50% · ×3"
		3:
			return "75% · ×2"
	return "100% · ×1"


# ---------------- 开关 ----------------

func _on_debug_hud_toggled(on: bool) -> void:
	var s = _coop_settings()
	if s != null:
		s.apply_debug_hud(on)
	var hud = get_tree().get_first_node_in_group("CoopNetDebugHud")
	if hud != null and is_instance_valid(hud) and hud.has_method("set_shown"):
		hud.call("set_shown", on)


func _on_upnp_toggled(on: bool) -> void:
	var s = _coop_settings()
	if s != null:
		s.call("apply_upnp_enabled", on)


# ---------------- 网络自检 ----------------

func _on_net_check_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	var coop = CoopNetScript.instance
	if coop == null or _net_check_result == null:
		return
	_net_check_result.text = tr("coop_net_check_hint")
	coop.call("run_network_selfcheck")


func _on_net_check_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_on_net_check_pressed()
		_net_check_button.accept_event()


func _on_netcheck_result(lines: PackedStringArray) -> void:
	if _net_check_result == null or not is_instance_valid(_net_check_result):
		return
	_net_check_result.text = "\n".join(lines)
