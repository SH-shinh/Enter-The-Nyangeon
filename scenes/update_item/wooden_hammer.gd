extends EquipItem

func _on_equip():
	PlayerData.critical_luck_mult *= 0.5
	PlayerData.global_damage_mult += 0.5

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.critical_luck_mult *= 0.5
	PlayerData.global_damage_mult += 0.5
