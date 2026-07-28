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
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.player_gun_shoot.connect(add_buff)

func first_activation():
	value = [buff_layer, buff_value, buff_erase_timer]

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "computational_unit":
		return
	if current_upgrade["computational_unit"]["quantity"] == 1:
		return
	num = current_upgrade["computational_unit"]["quantity"]

func add_buff(gun: Node):
	player.player_buff_manager.apply_buff(player_buff, value)
