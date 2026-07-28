extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.max_ammo_add += 50
	PlayerData.reload_timer_mult += 1
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "ammunition_box":
		return
	if current_upgrade["ammunition_box"]["quantity"] == 1:
		return
	num = current_upgrade["ammunition_box"]["quantity"]
	PlayerData.max_ammo_add += 50
	PlayerData.reload_timer_mult += 1
	PlayerData.update_player_ability()
