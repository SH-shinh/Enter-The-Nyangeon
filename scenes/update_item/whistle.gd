extends EquipItem

func _on_equip():
	PlayerData.bullet_speed_mult += 0.15

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_speed_mult += 0.15
