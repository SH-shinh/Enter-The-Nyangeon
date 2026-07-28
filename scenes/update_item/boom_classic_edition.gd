extends Node2D

var num: int

var player: Node
var hp_mult: float = 0.1

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.player_melee_hit_enemy.connect(add_t_hp)

func first_activation():
	hp_mult = 0.1
	player = get_tree().get_first_node_in_group("Player")
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "boom_classic_edition":
		return
	if current_upgrade["boom_classic_edition"]["quantity"] == 1:
		return
	num = current_upgrade["boom_classic_edition"]["quantity"]

func add_t_hp(body: Node):
	if body.hurt_damage >= body.stats.hp:
		var value: int = max(1, round(player.stats.max_hp * hp_mult))
		player.stats.t_hp += value
