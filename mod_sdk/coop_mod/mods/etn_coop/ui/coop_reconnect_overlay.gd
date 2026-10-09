extends CanvasLayer

## CoopReconnectOverlay：客机自动重连时的全屏遮罩（纯 mod，代码构建，无 .tscn）。
## 高 layer + PROCESS_MODE_ALWAYS，暂停/选人阶段也能显示；文字带循环点动画。

const FONT := preload("res://fonts/BoutiqueBitmap7x7_1.7.ttf")

var _label: Label = null
var _t: float = 0.0


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	var color := ColorRect.new()
	color.name = "ReconnectDim"
	color.color = Color(0, 0, 0, 0.55)
	color.set_anchors_preset(Control.PRESET_FULL_RECT)
	color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(color)

	_label = Label.new()
	_label.name = "ReconnectLabel"
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 4)
	_label.text = tr("coop_reconnecting")
	add_child(_label)


func _process(delta: float) -> void:
	_t += delta
	if _label != null:
		_label.text = tr("coop_reconnecting") + ".".repeat(int(_t * 2.0) % 4)
