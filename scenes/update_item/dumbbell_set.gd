extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.bullet_knockback_mult += 0.23
	PlayerData.bullet_damage_mult += 0.12
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "dumbbell_set":
		return
	if current_upgrade["dumbbell_set"]["quantity"] == 1:
		return
	num = current_upgrade["dumbbell_set"]["quantity"]
	PlayerData.bullet_knockback_mult += 0.23
	PlayerData.bullet_damage_mult += 0.12
	PlayerData.update_player_ability()
