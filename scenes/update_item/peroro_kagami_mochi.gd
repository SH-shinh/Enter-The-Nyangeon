extends Node2D

@onready var follow_icon = preload("res://scenes/update_item/peroro_kagami_mochi_icon.tscn")

var num: int
var group: Array = []

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	GameEvents.explosion_quantity.connect(add_damage_mult)
	var sprite_2d = follow_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "peroro_kagami_mochi":
		return
	if current_upgrade["peroro_kagami_mochi"]["quantity"] == 1:
		return
	num = current_upgrade["peroro_kagami_mochi"]["quantity"]

func add_damage_mult(size: int, explosion: Node):
	var mult_value = size * 0.1 + 1
	explosion.damage_mult = mult_value
