extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.fire_dot_layer_add += 3
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "weird_fireworks":
		return
	if current_upgrade["weird_fireworks"]["quantity"] == 1:
		return
	num = current_upgrade["weird_fireworks"]["quantity"]
	PlayerData.fire_dot_layer_add += 3
	PlayerData.update_player_ability()
