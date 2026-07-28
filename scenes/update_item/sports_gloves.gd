extends Node2D

var num: int

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.bullet_damage_add += 5
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "sports_gloves":
		return
	if current_upgrade["sports_gloves"]["quantity"] == 1:
		return
	num = current_upgrade["sports_gloves"]["quantity"]
	PlayerData.bullet_damage_add += 5
	PlayerData.update_player_ability()
