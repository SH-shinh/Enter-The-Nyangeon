extends Node2D
## Chihiro 近战「静电爆发」：以玩家为中心、覆盖 320 半径的一次性电爆（pixelfx thunderclap fork，34 帧烘焙）。
## 池化契约：is_idle / active_state / idle_state；由 chihiro_ps.release_static 调 play(origin)。

const POOL_ID := "chihiro_static_burst"
const FRAMES := preload("res://scenes/effects/chihiro_static_burst_frames.res")
## 画布 REACH=160，运行时放大到 320 半径
const SCALE := 320.0 / 160.0

@onready var sprite: AnimatedSprite2D = $Sprite

var is_idle: int = 1


func _ready() -> void:
	add_to_group("ChihiroStaticBurst")
	sprite.sprite_frames = FRAMES
	sprite.centered = false
	sprite.offset = -Vector2(176, 176)
	sprite.animation_finished.connect(idle_state)
	if not has_meta("remote_visual") and not has_meta("net_visual_id"):
		PoolManager.add_pool(POOL_ID, self)
	idle_state()


func play(pos: Vector2) -> void:
	global_position = pos
	scale = Vector2(SCALE, SCALE)
	active_state()


func active_state() -> void:
	visible = true
	is_idle = 0
	sprite.play("default")


## 远端克隆入口（coop_visual_sync）：只播动画，不播本地音效/屏震。
func network_apply_visual(_params: Dictionary) -> void:
	active_state()


func idle_state() -> void:
	is_idle = 1
	visible = false
	if sprite != null:
		sprite.stop()
