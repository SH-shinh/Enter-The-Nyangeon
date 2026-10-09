extends EquipItem

func _on_equip():
	PlayerData.max_hp_mult -= 0.2
	PlayerData.explosion_damage_mult += 0.4

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.max_hp_mult -= 0.2
	PlayerData.explosion_damage_mult += 0.4
