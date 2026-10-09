extends EquipItem

func _apply_effect(_quantity: int):
	PlayerData.global_damage_mult += 0.2
	PlayerData.critical_luck_add -= 15
