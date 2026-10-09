extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.dot_time_mult += 1
