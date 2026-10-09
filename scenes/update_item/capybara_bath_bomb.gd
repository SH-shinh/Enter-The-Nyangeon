extends EquipItem

func _on_equip():
	PlayerData.dot_damage_mult += 0.18

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.dot_damage_mult += 0.18
