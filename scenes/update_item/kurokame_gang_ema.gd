extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.max_hp_mult -= 0.12
	PlayerData.bullet_damage_mult += 0.3
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "kurokame_gang_ema":
		return
	if current_upgrade["kurokame_gang_ema"]["quantity"] == 1:
		return
	num = current_upgrade["kurokame_gang_ema"]["quantity"]
	PlayerData.max_hp_mult -= 0.12
	PlayerData.bullet_damage_mult += 0.3
	PlayerData.update_player_ability()
