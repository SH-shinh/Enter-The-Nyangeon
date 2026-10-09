extends EquipItem

func _on_equip():
	PlayerData.max_hp_mult += 1
	PlayerData.hurt_mult_mult += 1

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.max_hp_mult += 1
	PlayerData.hurt_mult_mult += 1
