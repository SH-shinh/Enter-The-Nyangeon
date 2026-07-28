extends Node2D

var num: int
var player: Node

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.player_hurt_hp.connect(add_t_hp)

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "mustache_crepe":
		return
	if current_upgrade["mustache_crepe"]["quantity"] == 1:
		return
	num = current_upgrade["mustache_crepe"]["quantity"]
	

func add_t_hp(hurt_hp: int):
	player.stats.t_hp += hurt_hp
