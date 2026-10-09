extends EquipItem

func _on_equip():
	PlayerData.luck_add += 12

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.luck_add += 12
