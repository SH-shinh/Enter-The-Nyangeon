extends CanvasLayer

## 网络诊断 HUD（mod，代码构建）。F4 开关；仅在联机会话下有意义。
## 数据来自 CoopNet.get_network_debug_text()，开关时联动 CoopNet.set_network_diag_enabled()。

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")

var _label: Label = null


func _ready() -> void:
	layer = 128
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_CENTER_TOP)
	margin.grow_horizontal = Control.GROW_DIRECTION_BOTH
	margin.offset_top = 12.0
	add_child(margin)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	margin.add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 4)
	_label.text = ""
	panel.add_child(_label)


func toggle() -> void:
	set_shown(not visible)


func set_shown(on: bool) -> void:
	visible = on
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		coop.call("set_network_diag_enabled", on)
	if on:
		_refresh()


func _process(_delta: float) -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	if _label == null:
		return
	var coop = CoopNetScript.instance
	if coop == null or not is_instance_valid(coop):
		_label.text = "[network] coop: offline"
		return
	var text: String = str(coop.call("get_network_debug_text"))
	var quality: String = str(coop.call("get_network_quality_debug_text"))
	_label.text = "[network: %s]  (F4/菜单关闭)\n%s" % [quality, text]
