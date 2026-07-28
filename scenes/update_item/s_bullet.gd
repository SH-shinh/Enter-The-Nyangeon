extends Node2D

var num: int

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.bullet_count_add += 2
	PlayerData.bullet_arc_add += 60
	PlayerData.bullet_damage_mult *= 0.4
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "s_bullet":
		return
	if current_upgrade["s_bullet"]["quantity"] == 1:
		return
	num = current_upgrade["s_bullet"]["quantity"]
	PlayerData.bullet_damage_mult += 0.1
	PlayerData.update_player_ability()
