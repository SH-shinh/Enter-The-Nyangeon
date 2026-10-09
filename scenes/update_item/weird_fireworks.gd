extends EquipItem

func _on_equip():
	PlayerData.fire_dot_layer_add += 3

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.fire_dot_layer_add += 3
