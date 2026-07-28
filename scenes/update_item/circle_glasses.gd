extends Node2D

var num: int

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.global_damage_mult += 0.2
	PlayerData.critical_luck_add -= 15
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "circle_glasses":
		return
	if current_upgrade["circle_glasses"]["quantity"] == 1:
		return
	num = current_upgrade["circle_glasses"]["quantity"]
	PlayerData.global_damage_mult += 0.2
	PlayerData.critical_luck_add -= 15
	PlayerData.update_player_ability()
