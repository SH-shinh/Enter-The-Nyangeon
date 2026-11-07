extends Node2D

## Serina EX 的视觉编排（挂在 serina_as 的 Aura 上）：
## - 常驻小光环（跟人）
## - 激活：爆发 + 入场光束（世界坐标，播一次）
## - 期间：光尘持续喷（世界坐标）、每次回血一段光点螺旋（挂在玩家身上）
## - 结束：环倒放收拢（无退场光束）

const HALO_FRAMES := preload("res://scenes/effects/serina_halo_frames.res")
const BURST_FRAMES := preload("res://scenes/effects/serina_burst_frames.res")
const BEAM_IN_FRAMES := preload("res://scenes/effects/serina_beam_in_frames.res")

@onready var _halo: AnimatedSprite2D = $Halo
@onready var _burst: AnimatedSprite2D = $Burst
@onready var _beam_in: AnimatedSprite2D = $BeamIn
@onready var _dust: Node = $Dust
@onready var _heal: Node = $HealFx


func _ready() -> void:
	for sprite: AnimatedSprite2D in [_burst, _beam_in]:
		sprite.animation_finished.connect(_on_once_finished.bind(sprite))
	_hide_all()


func play() -> void:
	var player := get_tree().get_first_node_in_group("Player") as Node2D
	_heal.set_target(player)
	_halo.sprite_frames = HALO_FRAMES
	_halo.visible = true
	_halo.play("default")
	_play_once(_burst, BURST_FRAMES)
	_play_once(_beam_in, BEAM_IN_FRAMES)
	_dust.start()


func stop() -> void:
	_halo.stop()
	_halo.visible = false
	_dust.stop()
	_heal.clear()
	_beam_in.stop()
	_beam_in.visible = false
	# 结束：环倒放收拢（取代原来的退场光束）
	_burst.stop()
	_burst.sprite_frames = BURST_FRAMES
	# 倒放的环要落在**当前**脚下（激活时是旧坐标，8 秒里玩家可能已经走开）
	_burst.global_position = global_position
	_burst.visible = true
	_burst.play_backwards("default")


## 每次回血：一段光点螺旋（挂在玩家身上，跟随移动）
func spawn_heal() -> void:
	_heal.spawn()


func _play_once(sprite: AnimatedSprite2D, frames: SpriteFrames) -> void:
	sprite.sprite_frames = frames
	sprite.global_position = global_position
	sprite.visible = true
	sprite.play("default")


func _on_once_finished(sprite: AnimatedSprite2D) -> void:
	sprite.stop()
	sprite.visible = false


func _hide_all() -> void:
	for sprite: AnimatedSprite2D in [_halo, _burst, _beam_in]:
		sprite.stop()
		sprite.visible = false
