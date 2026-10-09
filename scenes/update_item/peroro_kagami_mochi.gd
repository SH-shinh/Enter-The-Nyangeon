extends EquipItem

@onready var follow_icon = preload("res://scenes/update_item/peroro_kagami_mochi_icon.tscn")

var group: Array = []

func _on_equip():
	GameEvents.explosion_quantity.connect(add_damage_mult)
	var sprite_2d = follow_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true

func add_damage_mult(size: int, explosion: Node):
	var mult_value = size * 0.1 + 1
	explosion.damage_data.base_damage *= mult_value
