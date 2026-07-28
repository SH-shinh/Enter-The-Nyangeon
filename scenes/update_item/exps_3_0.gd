extends Node2D

@onready var EXPS_3_0_ICON: PackedScene = preload("res://scenes/update_item/exps_3_0_icon.tscn")

var rail_group: Array = []
var num: int

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.critical_luck_add += 5
	PlayerData.bullet_recoil_mult *= 0.85
	PlayerData.update_player_ability()
	var sprite_2d = EXPS_3_0_ICON.instantiate()
	rail_group = get_tree().get_nodes_in_group("Rail")
	for i in rail_group:
		if i.picatinny_rail_use == false:
			i.add_child(sprite_2d)
			i.picatinny_rail_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "exps_3_0":
		return
	if current_upgrade["exps_3_0"]["quantity"] == 1:
		return
	num = current_upgrade["exps_3_0"]["quantity"]
	PlayerData.critical_luck_add += 5
	PlayerData.bullet_recoil_mult *= 0.85
	PlayerData.update_player_ability()
