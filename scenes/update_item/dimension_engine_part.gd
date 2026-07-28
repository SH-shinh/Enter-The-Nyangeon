extends Node2D

var num: int
var player: Node

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	player = get_tree().get_first_node_in_group("Player")
	PlayerData.player_ability_changed_end.connect(melee_damage_count)
	melee_damage_count()

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "dimension_engine_part":
		return
	if current_upgrade["dimension_engine_part"]["quantity"] == 1:
		return
	num = current_upgrade["dimension_engine_part"]["quantity"]
	
func melee_damage_count():
	player.stats.kick_damage += player.stats.bullet_damage * 0.5
	PlayerData.emit_player_ability_changed()
