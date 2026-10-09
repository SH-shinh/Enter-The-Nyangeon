extends EquipItem

func _on_equip():
	PlayerData.collision_num_add += 1

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.collision_num_add += 1
