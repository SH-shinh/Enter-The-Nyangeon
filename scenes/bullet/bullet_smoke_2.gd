extends Node2D

## 命中烟（pixelfx 烘焙帧版）：6 帧 / 30fps / 0.2s / 48×48，1:1 像素、抖动淡出已烘进帧。
## 帧由 script/bake_pixelfx_fx.gd 生成（源：scenes/effects/pixelfx_bullet_smoke.gd）。
## 生命周期走 AnimatedSprite2D.animation_finished（引擎逐节点状态），
## 不再用 AnimationPlayer / method track / SceneTreeTimer 兜底。
## 池化契约见 scenes/manager/PoolManager.gd：idle_state() / is_idle / pool_id。

@export var pool_id: String = "bullet_smoke_2"

@onready var _sprite: AnimatedSprite2D = $Sprite

var is_idle: int = 1


func _ready() -> void:
	PoolManager.add_pool(pool_id, self)
	_sprite.animation_finished.connect(_on_animation_finished)
	idle_state()


func idle_state() -> void:
	reset_physics_interpolation()
	is_idle = 1
	_sprite.stop()
	visible = false
	global_position = Vector2.ZERO


func active_state() -> void:
	reset_physics_interpolation()
	is_idle = 0
	visible = true


## 兼容旧调用名（旧实现用它播放 RESET 动画清状态）。
func smoke_reset() -> void:
	_sprite.stop()


func smoke_anim() -> void:
	if not PoolManager.fx_allowed(&"bullet_smoke"):
		# 池槽不变式：拦截必须回池，否则永久占槽。
		idle_state()
		return
	active_state()
	# 池复用重播：停表 → 回到第 0 帧 → 起播，避免从上一轮残留帧开始。
	_sprite.stop()
	_sprite.set_frame_and_progress(0, 0.0)
	_sprite.play(&"default")


func _on_animation_finished() -> void:
	idle_state()
