extends EquipItem

func _on_equip():
	PlayerData.critical_damage_add += 0.28
	PlayerData.bullet_damage_mult -= 0.05

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.critical_damage_add += 0.28
	PlayerData.bullet_damage_mult -= 0.05
