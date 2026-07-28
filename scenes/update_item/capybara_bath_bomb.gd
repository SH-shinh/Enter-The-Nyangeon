extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.dot_damage_mult += 0.18
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "capybara_bath_bomb":
		return
	if current_upgrade["capybara_bath_bomb"]["quantity"] == 1:
		return
	num = current_upgrade["capybara_bath_bomb"]["quantity"]
	PlayerData.dot_damage_mult += 0.18
	PlayerData.update_player_ability()
