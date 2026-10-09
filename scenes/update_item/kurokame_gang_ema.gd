extends EquipItem

func _on_equip():
	PlayerData.max_hp_mult -= 0.12
	PlayerData.bullet_damage_mult += 0.3

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.max_hp_mult -= 0.12
	PlayerData.bullet_damage_mult += 0.3
