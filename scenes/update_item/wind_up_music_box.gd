extends EquipItem

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var wind_up_music_box_icon = preload("res://scenes/update_item/wind_up_music_box_icon.tscn")
@onready var add_buff_timer = $AddBuffTimer

var value: Array
var player: Node

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	add_buff_timer.timeout.connect(add_buff)
	value = [buff_layer, buff_value, buff_erase_timer]
	add_buff_timer.start()
	attach_hat_icon(wind_up_music_box_icon)

func _setup():
	GameEvents.player_gun_shoot.connect(shoot_restart)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	buff_layer += 10
	value = [buff_layer, buff_value, buff_erase_timer]

func shoot_restart(gun: Node):
	add_buff_timer.start()

func add_buff():
	player.player_buff_manager.apply_buff(player_buff, value)
