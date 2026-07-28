extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.collision_num_add += 1
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "elasticity_bullet":
		return
	if current_upgrade["elasticity_bullet"]["quantity"] == 1:
		return
	num = current_upgrade["elasticity_bullet"]["quantity"]
	PlayerData.collision_num_add += 1
	PlayerData.update_player_ability()
