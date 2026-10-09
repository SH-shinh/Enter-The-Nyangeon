extends CanvasLayer

signal left_end_start

@onready var animation_player: AnimationPlayer = $Node2D2/AnimationPlayer

var is_left_end_start:bool = false

func emit_left_end_start():
	left_end_start.emit()
	is_left_end_start = true

func play_left_start():
	GameEvents.begin_time_block("transition")
	animation_player.play("left_start")

func play_left_end():
	animation_player.play("left_end")
	is_left_end_start = false
	# 等擦除动画放完再解阻断，避免 wipe-out 期间被重新请求拖慢
	await animation_player.animation_finished
	GameEvents.end_time_block("transition")
