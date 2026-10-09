extends EquipItem

func _on_equip():
	PlayerData.explosion_range_mult += 0.25

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.explosion_range_mult += 0.25
