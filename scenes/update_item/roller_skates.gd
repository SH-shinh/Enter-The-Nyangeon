extends Node2D

var num: int

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.MAX_SPEED_mult += 1
	PlayerData.SPEED_TIME_add += 0.3
	PlayerData.update_player_ability()

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "roller_skates":
		return
	if current_upgrade["roller_skates"]["quantity"] == 1:
		return
	num = current_upgrade["roller_skates"]["quantity"]
