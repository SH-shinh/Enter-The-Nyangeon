extends Node2D

## 交互提示气泡：世界空间，跟随目标。
## 文字在上、图标在下，整体在主体内容区居中；动画基于气泡实际高度动态计算。

const ENTER_TIME := 0.1
const SLIDE_DISTANCE := 22.0
const GAP := 12.0

@export var key_icon_frames: SpriteFrames
@export var gamepad_icon_frames: SpriteFrames
@export var touch_icon_frames: SpriteFrames
## 触屏点击判定：以气泡实际矩形向外扩张的世界像素值。
@export var touch_margin: float = 20.0

@onready var root: Node2D = $Root
@onready var bubble: PanelContainer = $Root/Bubble
@onready var use_name: Label = $Root/Bubble/VBox/use_name
@onready var icon_holder: Control = $Root/Bubble/VBox/IconHolder
@onready var icon: AnimatedSprite2D = $Root/Bubble/VBox/IconHolder/Icon

var _showing: bool = false
var _target: Vector2 = Vector2.ZERO
var _tween: Tween = null

func _ready() -> void:
	visible = false
	# 气泡不吞输入：触摸需继续下传到 InteractionManager._unhandled_input。
	if not Game.game_mode_changed.is_connected(_refresh_icon):
		Game.game_mode_changed.connect(_refresh_icon)
	_refresh_icon()
	if not icon_holder.resized.is_connected(_center_icon):
		icon_holder.resized.connect(_center_icon)
	_center_icon()

func _process(_delta: float) -> void:
	global_position = _target
	_center_icon()

# 根据当前操作模式切换图标；未提供对应素材时回退到键盘图标占位
func _refresh_icon() -> void:
	var frames: SpriteFrames = key_icon_frames
	match Game.control_mode:
		1:
			if touch_icon_frames != null:
				frames = touch_icon_frames
		2:
			if gamepad_icon_frames != null:
				frames = gamepad_icon_frames
	if frames != null:
		icon.sprite_frames = frames
		icon.play("default")

func _center_icon() -> void:
	icon.position = icon_holder.size * 0.5

func show_prompt(text: String, world_pos: Vector2) -> void:
	_target = world_pos
	global_position = world_pos
	use_name.text = text
	var end_y := _end_y()
	if _showing:
		root.position.y = end_y
		return
	_showing = true
	visible = true
	root.position.y = end_y + SLIDE_DISTANCE
	root.modulate.a = 0.0
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(root, "position:y", end_y, ENTER_TIME)
	_tween.tween_property(root, "modulate:a", 1.0, ENTER_TIME)

func hide_prompt() -> void:
	if not _showing:
		return
	_showing = false
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(root, "position:y", _end_y() + SLIDE_DISTANCE, ENTER_TIME)
	_tween.tween_property(root, "modulate:a", 0.0, ENTER_TIME)
	_tween.chain().tween_callback(func(): visible = false)

func sync_position(world_pos: Vector2) -> void:
	_target = world_pos
	global_position = world_pos

## 供 InteractionManager 做触屏命中判定：气泡世界矩形向外扩 touch_margin。
func get_touch_rect() -> Rect2:
	return bubble.get_global_rect().grow(touch_margin)

func _end_y() -> float:
	var h: float = maxf(bubble.size.y, bubble.get_combined_minimum_size().y)
	return -h - GAP

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
