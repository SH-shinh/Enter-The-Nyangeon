extends EquipItem

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var student_council_hard_hat_icon = preload("res://scenes/update_item/student_council_hard_hat_icon.tscn")
@onready var animation_player = $Node2D/AnimationPlayer

var value: Array

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	value = [buff_layer, buff_value, buff_erase_timer]
	attach_hat_icon(student_council_hard_hat_icon)

func _setup():
	GameEvents.player_hurt_hp.connect(add_invalid_buff)
	GameEvents.player_hurt_t_hp.connect(add_invalid_buff)

func add_invalid_buff(hurt_hp: int):
	var max_hp_half = player.stats.max_hp * 0.5
	if hurt_hp >= max_hp_half:
		player.player_buff_manager.apply_buff(player_buff, value)
		animation_player.play("new_animation")
		SoundManager.play_sfx("EquipSounds5")
