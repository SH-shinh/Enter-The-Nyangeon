extends Node2D

var num: int
var player: Node

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	player = get_tree().get_first_node_in_group("Player")
	PlayerData.hurt_resis_mult += 1
	PlayerData.MAX_SPEED_value = player.stats.MAX_SPEED
	PlayerData.update_player_ability()

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "encyclopedia":
		return
	if current_upgrade["encyclopedia"]["quantity"] == 1:
		return
	num = current_upgrade["encyclopedia"]["quantity"]
