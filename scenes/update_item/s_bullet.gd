extends EquipItem

func _on_equip():
	PlayerData.bullet_count_add += 2
	PlayerData.bullet_arc_add += 60
	PlayerData.bullet_damage_mult *= 0.4

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_damage_mult += 0.1
