extends Node2D

## 圆盘碎片的发射迸发：参考库 ice/snowflake-burst 的 pop 段（去雪花 + 整体 1.5× 烘焙）。
## 一次性、池化：play 一次后回池；只在 follow_body 时取一次位置，不跟随目标。

const FRAMES := preload("res://scenes/effects/snowflake_burst_frames.res")
## 迸发中心在画布内的位置：画布 140×120、origin(70,106)，迸发点在脚底上方 48px。
const ORIGIN := Vector2(70, 58)
const POOL_ID := "snowflake_burst"

var is_idle: int = 1

@onready var _sprite: AnimatedSprite2D = $Sprite

func _ready() -> void:
	_sprite.sprite_frames = FRAMES
	_sprite.centered = false
	_sprite.offset = -ORIGIN
	_sprite.animation_finished.connect(_on_finished)
	PoolManager.add_pool(POOL_ID, self)
	idle_state()

func follow_body(body: Node) -> void:
	if body != null and is_instance_valid(body):
		global_position = body.global_position

## 联机视觉副本入口（mod 的 spawn_visual_effect 优先调这个）。
func active_state() -> void:
	play_anim()

func play_anim() -> void:
	is_idle = 0
	visible = true
	_sprite.visible = true
	_sprite.play("default")

func idle_state() -> void:
	is_idle = 1
	visible = false
	global_position = Vector2.ZERO
	if _sprite != null:
		_sprite.stop()
		_sprite.visible = false

func _on_finished() -> void:
	idle_state()
