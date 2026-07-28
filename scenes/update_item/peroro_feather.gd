extends Node2D

var num: int

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.luck_add += 12
	PlayerData.update_player_ability()

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "peroro_feather":
		return
	if current_upgrade["peroro_feather"]["quantity"] == 1:
		return
	num = current_upgrade["peroro_feather"]["quantity"]
	PlayerData.luck_add += 12
	PlayerData.update_player_ability()
