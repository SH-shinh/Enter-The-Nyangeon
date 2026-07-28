extends Node2D

var num: int

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.equip_damage_mult += 0.35
	PlayerData.dot_damage_mult += 0.35
	PlayerData.update_player_ability()

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "fish_cakes":
		return
	if current_upgrade["fish_cakes"]["quantity"] == 1:
		return
	num = current_upgrade["fish_cakes"]["quantity"]
	PlayerData.equip_damage_mult += 0.35
	PlayerData.dot_damage_mult += 0.35
	PlayerData.update_player_ability()
