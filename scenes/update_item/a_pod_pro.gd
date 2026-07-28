extends Node2D

var num: int
var kill_num: int

func _ready():
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.equip_kill_enemy.connect(equip_kill_count)

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "a_pod_pro":
		return
	if current_upgrade["a_pod_pro"]["quantity"] == 1:
		return
	num = current_upgrade["a_pod_pro"]["quantity"]

func equip_kill_count():
	kill_num += 1
	if kill_num >= 50:
		PlayerData.equip_damage_mult += 0.03
		PlayerData.update_player_ability()
		kill_num = 0
