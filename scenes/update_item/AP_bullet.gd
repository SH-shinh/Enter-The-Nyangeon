extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.bullet_penetrate_add += 1
	PlayerData.bullet_damage_mult -= 0.08
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "ap_bullet":
		return
	if current_upgrade["ap_bullet"]["quantity"] == 1:
		return
	num = current_upgrade["ap_bullet"]["quantity"]
	PlayerData.bullet_penetrate_add += 1
	PlayerData.bullet_damage_mult -= 0.08
	PlayerData.update_player_ability()
