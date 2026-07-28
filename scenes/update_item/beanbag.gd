extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.explosion_damage_mult += 0.15
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "beanbag":
		return
	if current_upgrade["beanbag"]["quantity"] == 1:
		return
	num = current_upgrade["beanbag"]["quantity"]
	PlayerData.explosion_damage_mult += 0.15
	PlayerData.update_player_ability()
