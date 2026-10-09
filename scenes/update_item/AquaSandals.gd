extends EquipItem

func _on_equip():
	PlayerData.MAX_SPEED_mult += 0.1

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.MAX_SPEED_mult += 0.1
