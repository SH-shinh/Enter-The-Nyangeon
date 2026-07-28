extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.max_t_hp_mult += 0.15
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "multivitamin_gummies":
		return
	if current_upgrade["multivitamin_gummies"]["quantity"] == 1:
		return
	num = current_upgrade["multivitamin_gummies"]["quantity"]
	PlayerData.max_t_hp_mult += 0.15
	PlayerData.update_player_ability()
