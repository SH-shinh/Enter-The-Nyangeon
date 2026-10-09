extends EquipItem

func _on_equip():
	PlayerData.dot_time_mult += 0.32

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.dot_time_mult += 0.32
