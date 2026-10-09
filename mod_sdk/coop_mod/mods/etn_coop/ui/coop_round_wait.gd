extends CanvasLayer

## 回合升级「等待所有人就绪」遮罩 / 断线重连「等待 XX 重新连接」轻量遮罩。
## 纯展示：不注册取消/返回输入（ESC 无效）。由 CoopFlow 打开/关闭，挂当前场景下，切场景自动释放。
## light 模式：无背景遮罩 + 小字号(12)顶部居中 + 鼠标穿透（回合进行中的重连等待，世界仍可操作）。

@onready var _label: Label = %ReadyLabel
@onready var _background: ColorRect = $Background
@onready var _center: CenterContainer = $Center

const BG_ALPHA_FULL: float = 0.68
const FONT_SIZE_FULL: int = 40
const FONT_SIZE_LIGHT: int = 12
const OUTLINE_SIZE_FULL: int = 6
const OUTLINE_SIZE_LIGHT: int = 3
const LIGHT_TOP_MARGIN: float = 12.0
const LIGHT_BAND_HEIGHT: float = 40.0


func _ready() -> void:
	if _label != null:
		_label.text = tr("coop_wait_all_ready")
		_apply_wrap()
	show_style(false)


# 设置文案与样式：light=true 用于断线重连（无黑底、小字号、顶部居中、鼠标穿透）
func show_message(text: String, light: bool = false) -> void:
	if _label != null and text != "":
		_label.text = text
	show_style(light)


func show_style(light: bool) -> void:
	if _background == null:
		return
	# light（断线重连）：取消整屏黑底
	_background.visible = not light
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE if light else Control.MOUSE_FILTER_STOP
	if not light:
		_background.color.a = BG_ALPHA_FULL
	if _label != null:
		_label.add_theme_font_size_override("font_size", FONT_SIZE_LIGHT if light else FONT_SIZE_FULL)
		_label.add_theme_constant_override("outline_size", OUTLINE_SIZE_LIGHT if light else OUTLINE_SIZE_FULL)
	if _center != null:
		if light:
			_center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
			_center.offset_top = LIGHT_TOP_MARGIN
			_center.offset_bottom = LIGHT_TOP_MARGIN + LIGHT_BAND_HEIGHT
		else:
			_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# 长玩家名换行兜底：按视口宽度限制 Label 宽度，超长自动换行不溢出
func _apply_wrap() -> void:
	var vw: float = 1280.0
	var vp := get_viewport()
	if vp != null:
		vw = vp.get_visible_rect().size.x
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = clampf(vw * 0.8, 200.0, 900.0)
