extends Node2D

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@onready var thermal_scope_icon: PackedScene = preload("res://scenes/update_item/thermal_scope_icon.tscn")

var rail_group: Array = []
var num: int
var group: Array
var value: Array
var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.player_shot_not_critical.connect(add_buff)

func first_activation():
	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.update_player_ability()
	var sprite_2d = thermal_scope_icon.instantiate()
	rail_group = get_tree().get_nodes_in_group("Rail")
	for i in rail_group:
		if i.picatinny_rail_use == false:
			i.add_child(sprite_2d)
			i.picatinny_rail_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "thermal_scope":
		return
	if current_upgrade["thermal_scope"]["quantity"] == 1:
		return
	num = current_upgrade["thermal_scope"]["quantity"]
	
	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.critical_damage_add += 0.15
	PlayerData.update_player_ability()

func add_buff(bullet_body: Node):
	if bullet_body.is_player_shoot == true:
		player.player_buff_manager.apply_buff(player_buff, value)
