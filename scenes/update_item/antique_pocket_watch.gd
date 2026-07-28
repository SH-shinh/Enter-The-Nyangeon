extends Node2D

var num: int

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.critical_luck_add += 3
	PlayerData.luck_add += 10
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "antique_pocket_watch":
		return
	if current_upgrade["antique_pocket_watch"]["quantity"] == 1:
		return
	num = current_upgrade["antique_pocket_watch"]["quantity"]
	PlayerData.critical_luck_add += 3
	PlayerData.luck_add += 10
	PlayerData.update_player_ability()
