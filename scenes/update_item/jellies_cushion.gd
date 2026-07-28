extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.bullet_speed_mult -= 0.15
	PlayerData.bullet_damage_mult += 0.1
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "jellies_cushion":
		return
	if current_upgrade["jellies_cushion"]["quantity"] == 1:
		return
	num = current_upgrade["jellies_cushion"]["quantity"]
	PlayerData.bullet_speed_mult -= 0.15
	PlayerData.bullet_damage_mult += 0.1
	PlayerData.update_player_ability()
