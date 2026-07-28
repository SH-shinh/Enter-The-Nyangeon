extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.hurt_resis_add += 2
	PlayerData.bullet_damage_mult -= 0.05
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "splashy_helmet":
		return
	if current_upgrade["splashy_helmet"]["quantity"] == 1:
		return
	num = current_upgrade["splashy_helmet"]["quantity"]
	PlayerData.hurt_resis_add += 2
	PlayerData.bullet_damage_mult -= 0.05
	PlayerData.update_player_ability()
