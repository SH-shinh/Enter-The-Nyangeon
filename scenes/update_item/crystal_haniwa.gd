extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.bullet_penetrate_add += 1000
	PlayerData.bullet_speed_mult -= 0.9
	PlayerData.bullet_scale_mult += 1
	PlayerData.max_bullet_speed = 150
	PlayerData.bullet_shoot_time_mult -= 0.5
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "crystal_haniwa":
		return
	if current_upgrade["crystal_haniwa"]["quantity"] == 1:
		return
	num = current_upgrade["crystal_haniwa"]["quantity"]
