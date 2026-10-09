extends EquipItem

func _on_equip():
	PlayerData.bullet_penetrate_add += 2

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.bullet_penetrate_add += 2
