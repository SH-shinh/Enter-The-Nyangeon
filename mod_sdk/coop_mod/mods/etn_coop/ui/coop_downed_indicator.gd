extends CanvasLayer

## CoopDownedIndicator：屏幕边缘箭头指引倒地队友（纯本地表现，无网络字段）。
## 每个观看者本地生成；只在联机且存在「屏幕外」的倒地队友时显示。
## 屏内倒地者不显示（交给其头顶已有的 HELP!）；本地玩家自己倒地时不显示。
## 箭头颜色红/白呼吸脉冲；标签为倒地者名字（CoopNet.get_display_name_for）。
## mod 内不使用 class_name，调用方一律 preload 引用。

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const ARROW_TEX := preload("res://ui/arrow_icon.png")
const FONT := preload("res://fonts/BoutiqueBitmap7x7_1.7.ttf")

const MAX_ARROWS: int = 8
const EDGE_MARGIN: float = 26.0
const ICON_SIZE: float = 40.0
const LABEL_W: float = 120.0
const LABEL_FONT_SIZE: int = 9
const PULSE_PERIOD: float = 0.5
const COLOR_DOWN := Color(0.95, 0.06, 0.15, 1.0)
const COLOR_BRIGHT := Color(1.0, 1.0, 1.0, 1.0)

var _arrows: Array[Node2D] = []
var _icons: Array[TextureRect] = []
var _labels: Array[Label] = []
var _probe: Control = null
var _pulse_t: float = 0.0


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	# CanvasLayer 无 get_viewport_rect()；用一个 Control 取「设计分辨率」坐标（与本体 Arrow.gd 同空间）
	_probe = Control.new()
	_probe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_probe)
	for i in MAX_ARROWS:
		var a := _make_arrow()
		a.visible = false
		add_child(a)
		_arrows.append(a)
		_icons.append(a.get_node("icon") as TextureRect)
		_labels.append(a.get_node("name") as Label)
	set_process(true)


func _make_arrow() -> Node2D:
	var root := Node2D.new()
	var icon := TextureRect.new()
	icon.name = "icon"
	icon.texture = ARROW_TEX
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.pivot_offset = Vector2(ICON_SIZE, ICON_SIZE) * 0.5
	icon.position = Vector2(-ICON_SIZE, -ICON_SIZE) * 0.5
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate = COLOR_DOWN
	root.add_child(icon)
	var label := Label.new()
	label.name = "name"
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(LABEL_W, 0)
	label.size = Vector2(LABEL_W, 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0.85, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 4)
	label.text = ""
	root.add_child(label)
	return root


func _process(delta: float) -> void:
	_pulse_t += delta
	var coop = CoopNetScript.instance
	if coop == null or not is_instance_valid(coop) or not bool(coop.get("is_lan_game")):
		_hide_all()
		return
	var local = coop.call("get_local_player")
	var cam := get_viewport().get_camera_2d()
	if local == null or not is_instance_valid(local) or cam == null:
		_hide_all()
		return
	if bool(local.get("is_downed")):
		_hide_all()
		return
	var zoom: Vector2 = cam.zoom
	if zoom.x == 0.0 or zoom.y == 0.0:
		_hide_all()
		return
	var viewport_size: Vector2 = _probe.get_viewport_rect().size if _probe != null else Vector2(640, 360)
	var world_size: Vector2 = viewport_size / zoom
	var center: Vector2 = cam.get_screen_center_position()
	var rect := Rect2(center - world_size * 0.5, world_size)
	var pulse: float = (sin(_pulse_t * TAU / PULSE_PERIOD) + 1.0) * 0.5
	var tint: Color = COLOR_DOWN.lerp(COLOR_BRIGHT, pulse)
	var peers = coop.get("player_by_peer_id")
	if peers == null:
		_hide_all()
		return
	var idx: int = 0
	for pid in peers.keys():
		if idx >= _arrows.size():
			break
		var p = peers[pid]
		if p == null or not is_instance_valid(p) or not (p is Node2D):
			continue
		if p.get("is_downed") != true:
			continue
		var wp: Vector2 = (p as Node2D).global_position
		if rect.has_point(wp):
			continue
		var arrow := _arrows[idx]
		var icon := _icons[idx]
		var label := _labels[idx]
		idx += 1
		var screen_pos: Vector2 = (wp - rect.position) * zoom
		var clamped: Vector2 = screen_pos.clamp(Vector2(EDGE_MARGIN, EDGE_MARGIN), viewport_size - Vector2(EDGE_MARGIN, EDGE_MARGIN))
		arrow.position = clamped
		arrow.visible = true
		icon.rotation = (wp - center).angle()
		icon.modulate = tint
		label.modulate = tint
		label.text = str(coop.call("get_display_name_for", int(pid)))
		var inward: Vector2 = (viewport_size * 0.5 - clamped)
		inward = inward.normalized() if inward.length_squared() > 0.0001 else Vector2.DOWN
		label.position = inward * (ICON_SIZE * 0.5 + 10.0) - Vector2(LABEL_W, 0.0) * 0.5
	for i in range(idx, _arrows.size()):
		_arrows[i].visible = false


func _hide_all() -> void:
	for a in _arrows:
		a.visible = false
