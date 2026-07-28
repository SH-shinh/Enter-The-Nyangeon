extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.bullet_shoot_time_mult += 0.08
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "rabbit_sticker":
		return
	if current_upgrade["rabbit_sticker"]["quantity"] == 1:
		return
	num = current_upgrade["rabbit_sticker"]["quantity"]
	PlayerData.bullet_shoot_time_mult += 0.08
	PlayerData.update_player_ability()
