extends EquipItem

@onready var muzzle_brake: PackedScene = preload("res://scenes/update_item/muzzle_brake_icon.tscn")
var group: Array

func _on_equip():
	PlayerData.bullet_recoil_mult -= 0.4
	group = get_tree().get_nodes_in_group("Muzzle")
	for i in group:
		if i.muzzle_use == false:
			var sprite_2d = muzzle_brake.instantiate()
			i.add_child(sprite_2d)
			i.muzzle_use = true

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_recoil_mult -= 0.4
