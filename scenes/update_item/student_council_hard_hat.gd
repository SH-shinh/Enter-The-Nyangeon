extends Node2D

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var student_council_hard_hat_icon = preload("res://scenes/update_item/student_council_hard_hat_icon.tscn")
@onready var animation_player = $Node2D/AnimationPlayer

var num: int
var player: Node
var value: Array
var group: Array = []

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.player_hurt_hp.connect(add_invalid_buff)
	GameEvents.player_hurt_t_hp.connect(add_invalid_buff)

func first_activation():
	value = [buff_layer, buff_value, buff_erase_timer]
	var sprite_2d = student_council_hard_hat_icon.instantiate()
	group = get_tree().get_nodes_in_group("Hat")
	for i in group:
		if i.hat_use == false:
			i.add_child(sprite_2d)
			i.hat_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "student_council_hard_hat":
		return
	if current_upgrade["student_council_hard_hat"]["quantity"] == 1:
		return
	num = current_upgrade["student_council_hard_hat"]["quantity"]

func add_invalid_buff(hurt_hp: int):
	var max_hp_half = player.stats.max_hp * 0.5
	if hurt_hp >= max_hp_half:
		player.player_buff_manager.apply_buff(player_buff, value)
		animation_player.play("new_animation")
		SoundManager.play_sfx("EquipSounds5")
