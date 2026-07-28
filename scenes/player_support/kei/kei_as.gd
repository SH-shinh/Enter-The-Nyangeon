extends Node2D

@export var body: Node
@export var support_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@export var buff_layer_2: int
@export var buff_value_2: float
@export var buff_erase_timer_2: float

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var collision_shape_2d: CollisionShape2D = $Area2D/CollisionShape2D
@onready var skill_timer: Timer = $SkillTimer
@onready var audio_stream_player_2d: AudioStreamPlayer2D = $AudioStreamPlayer2D

var value_player: Array
var value: Array
var as_is_active: bool = false

var emit_ready: bool = false
var rate_count: int = 0
var rate_base: int = 0

func _ready() -> void:
	value_player = [buff_layer, buff_value, buff_erase_timer]
	value = [buff_layer_2, buff_value_2, buff_erase_timer_2]
	GameEvents.round_upgrade.connect(skill_end)
	skill_timer.timeout.connect(skill_end)
	GameEvents.enemy_dead_score.connect(cost_count)

func cost_count(_score: int):
	if SupportData.now_cost < SupportData.ex_cost:
		SupportData.now_cost += 1
	else:
		if emit_ready == false:
			emit_ready = true
			GameEvents.emit_support_ex_ready()

func _unhandled_input(event: InputEvent) -> void:
	
	if event.is_action_pressed("EX_skill") :
		if SupportData.now_cost >= SupportData.ex_cost:
			skill_active()

func skill_active():
	if as_is_active == false:
		GameEvents.emit_support_ex_active()
		shoot_rate_buff()
		as_is_active = true
		skill_timer.start()
		collision_shape_2d.disabled = false
		audio_stream_player_2d.play()
		animation_player.play("as_anim")
		await animation_player.animation_finished
		animation_player.play("as_loop")

func skill_end():
	if as_is_active == true:
		shoot_rate_reset()
		as_is_active = false
		emit_ready = false
		SupportData.now_cost = 0
		collision_shape_2d.disabled = true
		animation_player.play_backwards("as_anim")
		GameEvents.emit_support_ex_end()

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

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		body.player_buff_manager.apply_buff(support_buff, value_player)
	
	if body.is_in_group("Summoned"):
		body.summoned_buff_manager.apply_buff(support_buff, value)


func _on_area_2d_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		body.player_buff_manager.remove_buff(support_buff)
	
	if body.is_in_group("Summoned"):
		body.summoned_buff_manager.remove_buff(support_buff)
