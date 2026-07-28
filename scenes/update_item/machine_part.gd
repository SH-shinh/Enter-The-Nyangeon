extends Node2D

var num: int

var summoned_manager: Node
var player: Node

var hurt_resis_mult: float = 0.05
var resis_count: float = 0

func _ready():
	summoned_manager = get_tree().get_first_node_in_group("SummonedManager")
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	summoned_manager.summoned_changed.connect(hurt_resis_count)

func first_activation():
	hurt_resis_mult = 0.05
	hurt_resis_count()

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "machine_part":
		return
	if current_upgrade["machine_part"]["quantity"] == 1:
		return
	num = current_upgrade["machine_part"]["quantity"]

func hurt_resis_count():
	
	PlayerData.hurt_mult_mult += resis_count
	var summoned_num = summoned_manager.summoned_group.size()
	resis_count = summoned_num * hurt_resis_mult
	PlayerData.hurt_mult_mult -= resis_count
	PlayerData.update_player_ability()
	
