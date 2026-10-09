extends EquipItem

func _on_equip():
	PlayerData.luck_add += 28
	PlayerData.bullet_damage_mult -= 0.05

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.luck_add += 28
	PlayerData.bullet_damage_mult -= 0.05
