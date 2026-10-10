extends SupportAS

@export var body: Node

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var aura: BuffAura = $Area2D
@onready var skill_timer: Timer = $SkillTimer
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D

# EX 动画代数：skill_end 时自增以作废挂起的 skill_active 协程，避免收招后回补 as_loop
var _as_gen: int = 0

var rate_count: int = 0
var rate_base: int = 0

func _on_ready() -> void:
	skill_timer.timeout.connect(skill_end)

func _on_skill_active() -> void:
	_as_gen += 1
	var gen := _as_gen
	shoot_rate_buff()
	skill_timer.start()
	aura.set_active(true)
	audio_stream_player_2d.play()
	animation_player.play("as_anim")
	await animation_player.animation_finished
	if as_is_active and gen == _as_gen:
		animation_player.play("as_loop")

func _on_skill_end() -> void:
	_as_gen += 1
	shoot_rate_reset()
	# 失活并兜底移除本机已施加的光环 buff（BuffAura 内部处理）
	aura.set_active(false)
	animation_player.play_backwards("as_anim")

func shoot_rate_buff():
	if body != null:
		rate_count = body.player.stats.bullet_shoot_time
		rate_base = body.stats.base_summoned_shoot_time
		body.stats.base_summoned_shoot_time = rate_count
		body.stats.update_body_ability()

func shoot_rate_reset():
	if body != null:
		body.stats.base_summoned_shoot_time = rate_base
		body.stats.update_body_ability()
