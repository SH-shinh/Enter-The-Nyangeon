extends EquipItem

func _on_equip():
	PlayerData.max_t_hp_mult += 0.15

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.max_t_hp_mult += 0.15
