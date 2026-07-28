extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.max_hp_mult += 1
	PlayerData.hurt_mult_mult += 1
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "macaron":
		return
	if current_upgrade["macaron"]["quantity"] == 1:
		return
	num = current_upgrade["macaron"]["quantity"]
	PlayerData.max_hp_mult += 1
	PlayerData.hurt_mult_mult += 1
	PlayerData.update_player_ability()
