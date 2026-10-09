extends EquipItem

func _on_equip():
	PlayerData.summoned_damage_add += 0.2

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.summoned_damage_add += 0.2
