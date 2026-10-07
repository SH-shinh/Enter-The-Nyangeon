extends "res://scenes/ball.gd"

## 准备房「开始球」：绿色，气泡提示"开始游戏"。
## - 非房主互动：切换自己的大厅「已准备」（头顶名牌上方显示，见 coop_name_tag）。
## - 房主互动：所有非房主都已准备则进入选人；否则在球气泡上方弹红字「需要所有玩家准备」。
## 运动/碰撞/交互完全复用本体 ball.gd（与测试房其它球一致）。
## 绿色贴图随 mod 打包（res://mods/etn_coop/sprites/item/green_ball.png）；因 mod pck 的 png
## 无导入资源，运行时用 Image.load_png_from_buffer 构建 SpriteFrames（帧顺序与本体黄球一致）。
## 保留本体 sprite_outline 材质（悬停高亮正常）。

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const HINT_FONT := preload("res://fonts/BoutiqueBitmap7x7_1.7.ttf")

const HINT_ANIM_TIME := 0.1
const HINT_HOLD := 2.0
const HINT_SLIDE := 10.0
const HINT_BASE_Y := -66.0
const HINT_WIDTH := 200.0

const GREEN_TEX_PATH := "res://mods/etn_coop/sprites/item/green_ball.png"
# 与本体 yellow_ball.tscn / 原 coop_start_ball.tscn 完全一致的 20 帧区域与顺序
const FRAME_REGIONS: Array[Vector2] = [
	Vector2(0, 0), Vector2(64, 0), Vector2(128, 0), Vector2(192, 0), Vector2(256, 0), Vector2(320, 0),
	Vector2(256, 192), Vector2(192, 192), Vector2(128, 192), Vector2(64, 192),
	Vector2(0, 64), Vector2(64, 128), Vector2(128, 128), Vector2(192, 128), Vector2(256, 128),
	Vector2(320, 64), Vector2(256, 64), Vector2(192, 64), Vector2(128, 64), Vector2(64, 64),
]

var _hint_label: Label = null
var _hint_tween: Tween = null


func _ready() -> void:
	super()
	prompt = tr("coop_start_game")
	interact_priority = 5
	_apply_green_frames()
	_build_hint_label()


func _apply_green_frames() -> void:
	if sprite_2d == null:
		return
	var tex := _load_green_texture()
	if tex == null:
		return
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", 12.0)
	frames.set_animation_loop("default", true)
	for r in FRAME_REGIONS:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(r.x, r.y, 64, 64)
		frames.add_frame("default", at)
	sprite_2d.sprite_frames = frames
	sprite_2d.frame = 0
	sprite_2d.frame_progress = 0.0


func _load_green_texture() -> Texture2D:
	if ResourceLoader.exists(GREEN_TEX_PATH):
		var t = load(GREEN_TEX_PATH)
		if t is Texture2D:
			return t
	var bytes := FileAccess.get_file_as_bytes(GREEN_TEX_PATH)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return null
	return ImageTexture.create_from_image(img)


func _build_hint_label() -> void:
	_hint_label = Label.new()
	_hint_label.name = "NotReadyHint"
	_hint_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.custom_minimum_size = Vector2(HINT_WIDTH, 0)
	_hint_label.size = Vector2(HINT_WIDTH, 0)
	_hint_label.position = Vector2(-HINT_WIDTH * 0.5, HINT_BASE_Y)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.z_index = 20
	_hint_label.add_theme_font_override("font", HINT_FONT)
	_hint_label.add_theme_font_size_override("font_size", 8)
	_hint_label.add_theme_color_override("font_color", Color(1.0, 0.333, 0.333, 1.0))
	_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_hint_label.add_theme_constant_override("outline_size", 4)
	_hint_label.text = tr("coop_players_not_ready")
	_hint_label.modulate.a = 0.0
	_hint_label.visible = false
	add_child(_hint_label)


func interact(_player: Node) -> void:
	var coop = CoopNetScript.instance
	if coop == null or not coop.is_lan_game:
		return
	if bool(coop.get("_select_flow_active")):
		return
	if multiplayer.is_server():
		if bool(coop.call("are_all_players_ready")):
			coop.call("request_begin_select")
		else:
			_show_not_ready_hint()
	else:
		coop.call("toggle_local_ready")


func _show_not_ready_hint() -> void:
	if _hint_label == null or not is_instance_valid(_hint_label):
		return
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_label.visible = true
	_hint_label.position.y = HINT_BASE_Y + HINT_SLIDE
	_hint_label.modulate.a = 0.0
	_hint_tween = create_tween()
	_hint_tween.set_parallel(true)
	_hint_tween.tween_property(_hint_label, "position:y", HINT_BASE_Y, HINT_ANIM_TIME)
	_hint_tween.tween_property(_hint_label, "modulate:a", 1.0, HINT_ANIM_TIME)
	_hint_tween.chain().tween_interval(HINT_HOLD)
	_hint_tween.chain().set_parallel(true)
	_hint_tween.tween_property(_hint_label, "position:y", HINT_BASE_Y + HINT_SLIDE, HINT_ANIM_TIME)
	_hint_tween.tween_property(_hint_label, "modulate:a", 0.0, HINT_ANIM_TIME)
	_hint_tween.chain().tween_callback(_hide_hint)


func _hide_hint() -> void:
	if _hint_label != null and is_instance_valid(_hint_label):
		_hint_label.visible = false
