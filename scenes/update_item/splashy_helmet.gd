extends EquipItem

func _on_equip():
	PlayerData.hurt_resis_add += 2
	PlayerData.bullet_damage_mult -= 0.05

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.hurt_resis_add += 2
	PlayerData.bullet_damage_mult -= 0.05
