extends Node2D

var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	GameEvents.player_melee_hit_enemy.connect(melee_damage_count)

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "peroro_wheel":
		return
	if current_upgrade["peroro_wheel"]["quantity"] == 1:
		return
	num = current_upgrade["peroro_wheel"]["quantity"]

func melee_damage_count(body: Node):
	if body.stats.hp == body.stats.max_hp:
		body.hurt_damage *= 2
