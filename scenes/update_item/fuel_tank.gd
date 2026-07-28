extends Node2D

@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@onready var fuel_tank_icon: PackedScene = preload("res://scenes/update_item/fuel_tank_icon.tscn")
var num: int
var group: Array
var value: Array
var player: Node
var add_layer: int = 1

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.enemy_body.connect(add_buff)

func first_activation():
	value = [buff_layer, buff_value, buff_erase_timer]
	add_layer = 1
	var sprite_2d = fuel_tank_icon.instantiate()
	group = get_tree().get_nodes_in_group("Muzzle")
	for i in group:
		if i.muzzle_use == false:
			i.add_child(sprite_2d)
			i.muzzle_use = true
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "fuel_tank":
		return
	if current_upgrade["fuel_tank"]["quantity"] == 1:
		return
	num = current_upgrade["fuel_tank"]["quantity"]
	#buff_layer += 2
	#buff_value *= 1
	#buff_erase_timer *= 1
	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.fire_dot_layer_add +=2
	add_layer += 1
	PlayerData.update_player_ability()

func add_buff(enemy_body: Node, bullet_body: Node):
	for i in add_layer:
		enemy_body.enemy_buff_manager.apply_buff(enemy_buff, value)
	
