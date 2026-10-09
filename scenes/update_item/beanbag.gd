extends EquipItem

func _on_equip():
	PlayerData.explosion_damage_mult += 0.15

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.explosion_damage_mult += 0.15
