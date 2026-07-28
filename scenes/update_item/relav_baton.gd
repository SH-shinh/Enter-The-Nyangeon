extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.explosion_range_mult += 0.25
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "relav_baton":
		return
	if current_upgrade["relav_baton"]["quantity"] == 1:
		return
	num = current_upgrade["relav_baton"]["quantity"]
	PlayerData.explosion_range_mult += 0.25
	PlayerData.update_player_ability()
