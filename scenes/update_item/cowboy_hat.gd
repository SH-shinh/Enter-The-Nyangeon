extends EquipItem

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var cowboy_hat_icon = preload("res://scenes/update_item/cowboy_hat_icon.tscn")

var value: Array
var player: Node

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	player.stats.ammo_changed.connect(add_buff)
	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.critical_damage_add += 0.25
	attach_hat_icon(cowboy_hat_icon)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.critical_damage_add += 0.25

func add_buff():
	if player.stats.ammo == player.stats.max_ammo:
		player.player_buff_manager.apply_buff(player_buff, value)
