extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.critical_damage_add += 0.28
	PlayerData.bullet_damage_mult -= 0.05
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "sakura_daifuku":
		return
	if current_upgrade["sakura_daifuku"]["quantity"] == 1:
		return
	num = current_upgrade["sakura_daifuku"]["quantity"]
	PlayerData.critical_damage_add += 0.28
	PlayerData.bullet_damage_mult -= 0.05
	PlayerData.update_player_ability()
