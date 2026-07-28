extends Node2D

var num: int

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.hurt_resis_add += 15
	PlayerData.MAX_SPEED_mult -= 0.1
	PlayerData.update_player_ability()

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "classical_poetry_anthology":
		return
	if current_upgrade["classical_poetry_anthology"]["quantity"] == 1:
		return
	num = current_upgrade["classical_poetry_anthology"]["quantity"]
	PlayerData.hurt_resis_add += 15
	PlayerData.MAX_SPEED_mult -= 0.1
	PlayerData.update_player_ability()
