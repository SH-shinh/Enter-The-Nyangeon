extends EquipItem

func _on_equip():
	PlayerData.critical_damage_add += 0.12

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.critical_damage_add += 0.12
