extends EquipItem

func _on_equip():
	PlayerData.bullet_knockback_mult += 0.23
	PlayerData.bullet_damage_mult += 0.12

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_knockback_mult += 0.23
	PlayerData.bullet_damage_mult += 0.12
