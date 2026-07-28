extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.max_ammo_add += 15
	PlayerData.bullet_damage_mult -= 0.05
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "drum_magazine":
		return
	if current_upgrade["drum_magazine"]["quantity"] == 1:
		return
	num = current_upgrade["drum_magazine"]["quantity"]
	PlayerData.max_ammo_add += 15
	PlayerData.bullet_damage_mult -= 0.05
	PlayerData.update_player_ability()
