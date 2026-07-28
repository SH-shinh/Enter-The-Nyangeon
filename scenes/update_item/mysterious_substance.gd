extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.max_hp_mult -= 0.2
	PlayerData.explosion_damage_mult += 0.4
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "mysterious_substance":
		return
	if current_upgrade["mysterious_substance"]["quantity"] == 1:
		return
	num = current_upgrade["mysterious_substance"]["quantity"]
	PlayerData.max_hp_mult -= 0.2
	PlayerData.explosion_damage_mult += 0.4
	PlayerData.update_player_ability()
