extends EquipItem

func _on_equip():
	PlayerData.bullet_penetrate_add += 1
	PlayerData.bullet_damage_mult -= 0.08

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_penetrate_add += 1
	PlayerData.bullet_damage_mult -= 0.08
