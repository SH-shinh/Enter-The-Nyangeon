extends Node2D

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var cowboy_hat_icon = preload("res://scenes/update_item/cowboy_hat_icon.tscn")

var group: Array =[]
var num: int
var value: Array
var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	player.stats.ammo_changed.connect(add_buff)
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.critical_damage_add += 0.25
	PlayerData.update_player_ability()
	var sprite_2d = cowboy_hat_icon.instantiate()
	group = get_tree().get_nodes_in_group("Hat")
	for i in group:
		if i.hat_use == false:
			i.add_child(sprite_2d)
			i.hat_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "cowboy_hat":
		return
	if current_upgrade["cowboy_hat"]["quantity"] == 1:
		return
	num = current_upgrade["cowboy_hat"]["quantity"]
	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.critical_damage_add += 0.25
	PlayerData.update_player_ability()

func add_buff():
	if player.stats.ammo == player.stats.max_ammo:
		player.player_buff_manager.apply_buff(player_buff, value)
