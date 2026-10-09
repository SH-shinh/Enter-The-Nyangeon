extends EquipItem

func _on_equip():
	PlayerData.bullet_shoot_time_mult -= 0.06
	PlayerData.bullet_damage_mult += 0.15

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_shoot_time_mult -= 0.06
	PlayerData.bullet_damage_mult += 0.15
