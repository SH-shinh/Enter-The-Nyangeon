extends CanvasLayer

## 准备房右上角房间标识：LAN 显示本机 IP:端口，Relay 显示房间码。
## 常驻根节点；仅联机会话时可见。
## 黑色底板按文字自适应：每帧 reset_size + 手动贴右上角（不再固定宽度）。

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const MENU_FONT := preload("res://fonts/BoutiqueBitmap7x7_1.7.ttf")

const MARGIN_TOP: float = 8.0
const MARGIN_RIGHT: float = 8.0

var _label: Label
var _panel: PanelContainer
var _last_touch_frame: int = -1


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_panel.gui_input.connect(_on_panel_input)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_font_override("font", MENU_FONT)
	_label.add_theme_font_size_override("font_size", 10)
	_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85, 1.0))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 4)
	_panel.add_child(_label)
	_panel.visible = false


func _process(_delta: float) -> void:
	var coop = CoopNetScript.instance
	var text: String = ""
	# 仅准备房（test_room）且未进入选人时显示；选人/关卡内隐藏（关卡内在暂停页显示）
	if coop != null and is_instance_valid(coop) and bool(coop.is_lan_game):
		var in_lobby: bool = str(coop.get("current_scene_path")).contains("test_room")
		var selecting: bool = bool(coop.get("_select_flow_active"))
		if in_lobby and not selecting:
			text = str(coop.call("get_room_display_text"))
	var shown: bool = text != ""
	if _panel.visible != shown:
		_panel.visible = shown
	if _label.text != text:
		_label.text = text
	_fit_to_text()


# 黑色底板按文字宽度自适应，右缘固定距屏幕右 MARGIN_RIGHT。
func _fit_to_text() -> void:
	_panel.reset_size()
	var vp := get_viewport()
	if vp == null:
		return
	var vw: float = vp.get_visible_rect().size.x
	_panel.position = Vector2(vw - _panel.size.x - MARGIN_RIGHT, MARGIN_TOP)


# 点击/触摸房间标识 → 复制地址（走 CoopNet 统一复制 + toast）
func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_last_touch_frame = Engine.get_process_frames()
		_copy()
		_panel.accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _last_touch_frame == Engine.get_process_frames():
			return
		_copy()
		_panel.accept_event()


func _copy() -> void:
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		coop.call("copy_room_address_to_clipboard")
