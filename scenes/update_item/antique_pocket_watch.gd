extends EquipItem

func _on_equip():
	PlayerData.critical_luck_add += 3
	PlayerData.luck_add += 10

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.critical_luck_add += 3
	PlayerData.luck_add += 10
