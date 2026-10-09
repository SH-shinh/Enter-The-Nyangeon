extends EquipItem

func _on_equip():
	PlayerData.equip_damage_mult += 0.35
	PlayerData.dot_damage_mult += 0.35

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.equip_damage_mult += 0.35
	PlayerData.dot_damage_mult += 0.35
