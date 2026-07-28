extends Node2D

var num: int
var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.max_hp_add += 20
	PlayerData.update_player_ability()
	player.stats.hp += 20

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "school_bag":
		return
	if current_upgrade["school_bag"]["quantity"] == 1:
		return
	num = current_upgrade["school_bag"]["quantity"]
	PlayerData.max_hp_add += 20
	PlayerData.update_player_ability()
	player.stats.hp += 20
