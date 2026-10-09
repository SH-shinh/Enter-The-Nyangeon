extends EquipItem

func _on_equip():
	PlayerData.equip_damage_mult += 0.25

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.equip_damage_mult += 0.25
