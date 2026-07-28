extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.MAX_SPEED_mult += 0.1
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "aqua_sandals":
		return
	if current_upgrade["aqua_sandals"]["quantity"] == 1:
		return
	num = current_upgrade["aqua_sandals"]["quantity"]
	PlayerData.MAX_SPEED_mult += 0.1
	PlayerData.update_player_ability()
