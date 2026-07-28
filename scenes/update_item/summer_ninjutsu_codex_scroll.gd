extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.luck_add += 28
	PlayerData.bullet_damage_mult -= 0.05
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "summer_ninjutsu_codex_scroll":
		return
	if current_upgrade["summer_ninjutsu_codex_scroll"]["quantity"] == 1:
		return
	num = current_upgrade["summer_ninjutsu_codex_scroll"]["quantity"]
	PlayerData.luck_add += 28
	PlayerData.bullet_damage_mult -= 0.05
	PlayerData.update_player_ability()
