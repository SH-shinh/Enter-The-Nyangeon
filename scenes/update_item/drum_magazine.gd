extends EquipItem

func _on_equip():
	PlayerData.max_ammo_add += 15
	PlayerData.bullet_damage_mult -= 0.05

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.max_ammo_add += 15
	PlayerData.bullet_damage_mult -= 0.05
