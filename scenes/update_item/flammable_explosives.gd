extends Node2D

@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@onready var flammable_explosives_icon = preload("res://scenes/update_item/flammable_explosives_icon.tscn")
var num: int
var value: Array = []
var add_layer: int
var group: Array = []

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.enemy_explosion_hurt.connect(fire_explosion)

func first_activation():
	value = [buff_layer, buff_value, buff_erase_timer]
	add_layer = 1
	PlayerData.update_player_ability()
	var sprite_2d = flammable_explosives_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "flammable_explosives":
		return
	if current_upgrade["flammable_explosives"]["quantity"] == 1:
		return
	num = current_upgrade["flammable_explosives"]["quantity"]
	value = [buff_layer, buff_value, buff_erase_timer]
	add_layer += 1
	PlayerData.update_player_ability()

func fire_explosion(enemy_body: Node):
	for i in add_layer:
		enemy_body.enemy_buff_manager.apply_buff(enemy_buff, value)
