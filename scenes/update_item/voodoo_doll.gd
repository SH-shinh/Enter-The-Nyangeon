extends EquipItem

@onready var voodoo_doll_icon = preload("res://scenes/update_item/voodoo_doll_icon.tscn")

var group: Array = []

func _on_equip():
	PlayerData.bullet_damage_mult += 0.5
	PlayerData.hurt_mult_mult += 0.5
	var sprite_2d = voodoo_doll_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_damage_mult += 0.5
	PlayerData.hurt_mult_mult += 0.5
