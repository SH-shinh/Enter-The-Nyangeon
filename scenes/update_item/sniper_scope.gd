extends Node2D

@onready var sniper_scope_icon: PackedScene = preload("res://scenes/update_item/sniper_scope_icon.tscn")

var rail_group: Array
var num: int

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.critical_luck_add += 10
	PlayerData.bullet_shoot_time_mult -= 0.1
	PlayerData.critical_damage_add += 0.25
	PlayerData.update_player_ability()
	var sprite_2d = sniper_scope_icon.instantiate()
	rail_group = get_tree().get_nodes_in_group("Rail")
	for i in rail_group:
		if i.picatinny_rail_use == false:
			i.add_child(sprite_2d)
			i.picatinny_rail_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "sniper_scope":
		return
	if current_upgrade["sniper_scope"]["quantity"] == 1:
		return
	num = current_upgrade["sniper_scope"]["quantity"]
	PlayerData.critical_luck_add += 10
	PlayerData.bullet_shoot_time_mult -= 0.1
	PlayerData.critical_damage_add += 0.25
	PlayerData.update_player_ability()
