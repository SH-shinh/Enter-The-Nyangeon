extends Node2D

var num: int
var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.hurt_mult_mult *= 0.92
	PlayerData.max_hp_add += 24
	PlayerData.update_player_ability()
	player.stats.hp += 24

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "tactical_satchel":
		return
	if current_upgrade["tactical_satchel"]["quantity"] == 1:
		return
	num = current_upgrade["tactical_satchel"]["quantity"]
	PlayerData.hurt_mult_mult *= 0.92
	PlayerData.max_hp_add += 24
	PlayerData.update_player_ability()
	player.stats.hp += 24
