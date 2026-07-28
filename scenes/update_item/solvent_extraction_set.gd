extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	GameEvents.player_melee_hit_enemy.connect(melee_damage_count)

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "solvent_extraction_set":
		return
	if current_upgrade["solvent_extraction_set"]["quantity"] == 1:
		return
	num = current_upgrade["solvent_extraction_set"]["quantity"]

func melee_damage_count(body: Node):
	body.hurt_damage *= (4 - (float(body.stats.hp) / float(body.stats.max_hp)) * 3.0)
