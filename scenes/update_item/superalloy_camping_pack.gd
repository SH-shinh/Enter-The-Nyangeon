extends Node2D


var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.bullet_penetrate_add += 2
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "superalloy_camping_pack":
		return
	if current_upgrade["superalloy_camping_pack"]["quantity"] == 1:
		return
	num = current_upgrade["superalloy_camping_pack"]["quantity"]
	PlayerData.bullet_penetrate_add += 2
	PlayerData.update_player_ability()
