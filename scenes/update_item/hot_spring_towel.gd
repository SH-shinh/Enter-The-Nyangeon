extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.dot_damage_mult += 0.5
	PlayerData.dot_time_mult -= 0.25
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "hot_spring_towel":
		return
	if current_upgrade["hot_spring_towel"]["quantity"] == 1:
		return
	num = current_upgrade["hot_spring_towel"]["quantity"]
	PlayerData.dot_damage_mult += 0.5
	PlayerData.dot_time_mult -= 0.25
	PlayerData.update_player_ability()
