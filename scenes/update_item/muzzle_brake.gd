extends Node2D

@onready var muzzle_brake: PackedScene = preload("res://scenes/update_item/muzzle_brake_icon.tscn")
var num: int
var group: Array

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.bullet_recoil_mult -= 0.4
	PlayerData.update_player_ability()
	var sprite_2d = muzzle_brake.instantiate()
	group = get_tree().get_nodes_in_group("Muzzle")
	for i in group:
		if i.muzzle_use == false:
			i.add_child(sprite_2d)
			i.muzzle_use = true
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "muzzle_brake":
		return
	if current_upgrade["muzzle_brake"]["quantity"] == 1:
		return
	num = current_upgrade["muzzle_brake"]["quantity"]
	PlayerData.bullet_recoil_mult -= 0.4
	PlayerData.update_player_ability()
