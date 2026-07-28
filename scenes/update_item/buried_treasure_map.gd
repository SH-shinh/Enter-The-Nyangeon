extends Node2D

var num: int
var player_luck: int = 0
var luck_add: int = 0
var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	PlayerData.player_ability_changed_end.connect(luck_count)

func first_activation():
	luck_count()

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "buried_treasure_map":
		return
	if current_upgrade["buried_treasure_map"]["quantity"] == 1:
		return
	num = current_upgrade["buried_treasure_map"]["quantity"]


func luck_count():
	luck_add = max(0, round(player.stats.luck * 0.3))
	player.stats.critical_luck += luck_add
	PlayerData.emit_player_ability_changed()
