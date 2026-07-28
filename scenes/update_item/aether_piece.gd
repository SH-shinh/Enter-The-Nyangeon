extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.bullet_shoot_time_mult -= 0.06
	PlayerData.bullet_damage_mult += 0.15
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "aether_piece":
		return
	if current_upgrade["aether_piece"]["quantity"] == 1:
		return
	num = current_upgrade["aether_piece"]["quantity"]
	PlayerData.bullet_shoot_time_mult -= 0.06
	PlayerData.bullet_damage_mult += 0.15
	PlayerData.update_player_ability()
