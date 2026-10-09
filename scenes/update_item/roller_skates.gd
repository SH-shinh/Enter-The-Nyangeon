extends EquipItem

func _on_equip():
	PlayerData.MAX_SPEED_mult += 1
	PlayerData.SPEED_TIME_add += 0.3
