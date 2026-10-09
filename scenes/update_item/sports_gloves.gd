extends EquipItem

func _on_equip():
	PlayerData.bullet_damage_add += 5

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_damage_add += 5
