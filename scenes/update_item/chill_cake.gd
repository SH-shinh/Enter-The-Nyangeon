extends Node2D

var num: int
var kill_num: int = 0

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.enemy_dead_hurt_damage.connect(kill_num_count)

func first_activation():
	PlayerData.max_hp_add += 5
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "chill_cake":
		return
	if current_upgrade["chill_cake"]["quantity"] == 1:
		return
	num = current_upgrade["chill_cake"]["quantity"]

func kill_num_count(_hurt_damage: int):
	kill_num += 1
	if kill_num >= 80:
		kill_num = 0
		add_max_hp()

func add_max_hp():
	PlayerData.max_hp_add += 1
	PlayerData.update_player_ability()
