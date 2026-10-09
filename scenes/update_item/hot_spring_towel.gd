extends EquipItem

func _on_equip():
	PlayerData.dot_damage_mult += 0.5
	PlayerData.dot_time_mult -= 0.25

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.dot_damage_mult += 0.5
	PlayerData.dot_time_mult -= 0.25
