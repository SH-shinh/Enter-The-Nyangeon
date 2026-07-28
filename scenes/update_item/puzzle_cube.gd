extends Node2D

@onready var follow_icon = preload("res://scenes/update_item/puzzle_cube_icon.tscn")

var num: int
var group: Array = []

var overflow_count: int = 0
var overflow_cd: int = 0

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	GameEvents.enemy_dead_overflow_hp.connect(dead_overflow_damage)
	GameEvents.global_time_count.connect(time_count)
	var sprite_2d = follow_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "puzzle_cube":
		return
	if current_upgrade["puzzle_cube"]["quantity"] == 1:
		return
	num = current_upgrade["puzzle_cube"]["quantity"]

func time_count():
	if overflow_cd > 0:
		overflow_cd -= 1
		if overflow_cd <= 0:
			overflow_count_add()

func overflow_count_add():
	if !PoolManager.enemies_group.is_empty():
		var i = randi_range(0, PoolManager.enemies_group.size() - 1)
		PoolManager.enemies_group[i].hurt_damage = overflow_count
		PoolManager.enemies_group[i].emit_signal("is_hurt")

func dead_overflow_damage(overflow_hp: int):
	if overflow_cd <= 0:
		overflow_count = clamp(overflow_hp, 1, 9223372036854775807)
		overflow_cd = 1
