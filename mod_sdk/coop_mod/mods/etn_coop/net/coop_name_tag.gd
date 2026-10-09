extends Label

## CoopNameTag：联机玩家头顶名牌 + 生命条（仅远端）+ 倒地 HELP!（仅远端）+ 大厅「已准备」子标签。
## 作为玩家节点的子节点，每帧把自身对齐到玩家 AnimatedSprite2D 的垂直偏移，
## 从而在跳跃（sprite_2d.position.y 变化）时同步上移；不随瞄准旋转。
## 垂直布局（上->下，均为名牌本地坐标）：
##   HelpTag（仅远端倒地时可见，上下浮动）  y = HELP_BASE_Y
##   ReadyTag（已准备）                      y = READY_BASE_Y
##   CoopHealthBar（仅远端）                 y = HEALTH_BAR_Y
##   名牌文本                                y = 0
## 字体固定为 BoutiqueBitmap7x7_1.7（不做跨语言强锁，LocaleFont 仍可替换）。
## mod 内不使用 class_name，调用方一律 preload 引用。

const NAME_FONT := preload("res://fonts/BoutiqueBitmap7x7_1.7.ttf")
const HealthBarScript := preload("res://mods/etn_coop/net/coop_health_bar.gd")

const TAG_WIDTH: float = 200.0
const TAG_OFFSET: float = 61.0

const HEALTH_BAR_W: float = 44.0
const HEALTH_BAR_Y: float = -6.0

const READY_ANIM_TIME: float = 0.1
const READY_SLIDE: float = 8.0
const READY_BASE_Y: float = -17.0

const HELP_BASE_Y: float = -31.0
const HELP_FLOAT_AMP: float = 2.0
const HELP_FLOAT_PERIOD: float = 1.0

var _target: Node2D = null
var _player: Node = null
var _ready_label: Label = null
var _ready_state: bool = false
var _ready_tween: Tween = null
var _health_bar: Control = null
var _help_label: Label = null
var _is_remote: bool = false
var _help_t: float = 0.0
var _offline: bool = false
var _display_text: String = ""


func setup(player: Node, display_text: String) -> void:
	_player = player
	_target = player.get("sprite_2d") as Node2D if player != null else null
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	custom_minimum_size = Vector2(TAG_WIDTH, 0)
	size = Vector2(TAG_WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10
	add_theme_font_override("font", NAME_FONT)
	add_theme_font_size_override("font_size", 8)
	add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	add_theme_constant_override("outline_size", 4)
	_display_text = display_text
	text = display_text
	position = Vector2(-TAG_WIDTH * 0.5, -TAG_OFFSET)
	_build_ready_label()
	set_process(true)


func set_display_text(value: String) -> void:
	_display_text = value
	if not _offline:
		text = value


# 断线重连宽限期间：名牌灰显并改文案（仅其它端可见的该玩家镜像）。
func set_offline(value: bool) -> void:
	if _offline == value:
		return
	_offline = value
	if value:
		text = tr("coop_peer_offline")
		modulate = Color(0.55, 0.55, 0.55, 1.0)
	else:
		text = _display_text
		modulate = Color(1, 1, 1, 1)


# 仅远端玩家调用：挂生命条并启用倒地 HELP!。
func attach_health_bar(player: Node) -> void:
	_is_remote = true
	if _health_bar == null or not is_instance_valid(_health_bar):
		_health_bar = HealthBarScript.new()
		_health_bar.name = "CoopHealthBar"
		_health_bar.call("setup", player)
		add_child(_health_bar)
	_health_bar.position = Vector2(TAG_WIDTH * 0.5 - HEALTH_BAR_W * 0.5, HEALTH_BAR_Y)
	_build_help_label()


func _build_help_label() -> void:
	if _help_label != null and is_instance_valid(_help_label):
		return
	_help_label = Label.new()
	_help_label.name = "HelpTag"
	_help_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_help_label.custom_minimum_size = Vector2(TAG_WIDTH, 0)
	_help_label.size = Vector2(TAG_WIDTH, 0)
	_help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_label.add_theme_font_override("font", NAME_FONT)
	_help_label.add_theme_font_size_override("font_size", 12)
	_help_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_help_label.add_theme_color_override("font_outline_color", Color(0.85, 0, 0, 1))
	_help_label.add_theme_constant_override("outline_size", 4)
	_help_label.text = tr("coop_help")
	_help_label.position = Vector2(0, HELP_BASE_Y)
	_help_label.visible = false
	add_child(_help_label)


func _build_ready_label() -> void:
	if _ready_label != null and is_instance_valid(_ready_label):
		return
	_ready_label = Label.new()
	_ready_label.name = "ReadyTag"
	_ready_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ready_label.custom_minimum_size = Vector2(TAG_WIDTH, 0)
	_ready_label.size = Vector2(TAG_WIDTH, 0)
	_ready_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_label.add_theme_font_override("font", NAME_FONT)
	_ready_label.add_theme_font_size_override("font_size", 8)
	_ready_label.add_theme_color_override("font_color", Color(0.35, 1.0, 0.5, 1.0))
	_ready_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_ready_label.add_theme_constant_override("outline_size", 4)
	_ready_label.text = tr("coop_prepared")
	_ready_label.position = Vector2(0, READY_BASE_Y)
	_ready_label.modulate.a = 0.0
	_ready_label.visible = false
	add_child(_ready_label)


func set_ready(value: bool) -> void:
	if _ready_state == value:
		return
	_ready_state = value
	if _ready_label == null or not is_instance_valid(_ready_label):
		return
	_kill_ready_tween()
	if value:
		_ready_label.visible = true
		_ready_label.position.y = READY_BASE_Y + READY_SLIDE
		_ready_label.modulate.a = 0.0
		_ready_tween = create_tween().set_parallel(true)
		_ready_tween.tween_property(_ready_label, "position:y", READY_BASE_Y, READY_ANIM_TIME)
		_ready_tween.tween_property(_ready_label, "modulate:a", 1.0, READY_ANIM_TIME)
	else:
		_ready_tween = create_tween().set_parallel(true)
		_ready_tween.tween_property(_ready_label, "position:y", READY_BASE_Y + READY_SLIDE, READY_ANIM_TIME)
		_ready_tween.tween_property(_ready_label, "modulate:a", 0.0, READY_ANIM_TIME)
		_ready_tween.chain().tween_callback(_hide_ready_label)


func _hide_ready_label() -> void:
	if _ready_label != null and is_instance_valid(_ready_label):
		_ready_label.visible = false


func _kill_ready_tween() -> void:
	if _ready_tween != null and _ready_tween.is_valid():
		_ready_tween.kill()


func _process(_delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		visible = false
		return
	visible = true
	position.x = -TAG_WIDTH * 0.5
	position.y = _target.position.y - TAG_OFFSET
	_update_help(_delta)


func _update_help(delta: float) -> void:
	if not _is_remote or _help_label == null or not is_instance_valid(_help_label):
		return
	var downed: bool = _player != null and is_instance_valid(_player) and _player.get("is_downed") == true
	if not downed:
		if _help_label.visible:
			_help_label.visible = false
		_help_t = 0.0
		return
	if not _help_label.visible:
		_help_label.visible = true
	_help_t += delta
	_help_label.position.y = HELP_BASE_Y + sin(_help_t * TAU / HELP_FLOAT_PERIOD) * HELP_FLOAT_AMP
