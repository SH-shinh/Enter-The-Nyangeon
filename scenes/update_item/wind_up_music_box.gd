extends Node2D

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var wind_up_music_box_icon = preload("res://scenes/update_item/wind_up_music_box_icon.tscn")
@onready var add_buff_timer = $AddBuffTimer

var group: Array =[]
var num: int
var value: Array
var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	add_buff_timer.timeout.connect(add_buff)
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.player_gun_shoot.connect(shoot_restart)

func first_activation():
	value = [buff_layer, buff_value, buff_erase_timer]
	add_buff_timer.start()
	PlayerData.update_player_ability()
	var sprite_2d = wind_up_music_box_icon.instantiate()
	group = get_tree().get_nodes_in_group("Hat")
	for i in group:
		if i.hat_use == false:
			i.add_child(sprite_2d)
			i.hat_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "wind_up_music_box":
		return
	if current_upgrade["wind_up_music_box"]["quantity"] == 1:
		return
	num = current_upgrade["wind_up_music_box"]["quantity"]
	buff_layer += 10
	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.update_player_ability()

func shoot_restart(gun: Node):
	add_buff_timer.start()

func add_buff():
	player.player_buff_manager.apply_buff(player_buff, value)
