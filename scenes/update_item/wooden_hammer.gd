extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.critical_luck_mult *= 0.5
	PlayerData.global_damage_mult += 0.5
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "wooden_hammer":
		return
	if current_upgrade["wooden_hammer"]["quantity"] == 1:
		return
	num = current_upgrade["wooden_hammer"]["quantity"]
	PlayerData.critical_luck_mult *= 0.5
	PlayerData.global_damage_mult += 0.5
	PlayerData.update_player_ability()
