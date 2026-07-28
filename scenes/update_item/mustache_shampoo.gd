extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.dot_time_mult += 0.32
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "mustache_shampoo":
		return
	if current_upgrade["mustache_shampoo"]["quantity"] == 1:
		return
	num = current_upgrade["mustache_shampoo"]["quantity"]
	PlayerData.dot_time_mult += 0.32
	PlayerData.update_player_ability()
