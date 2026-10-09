extends EquipItem

func _on_equip():
	PlayerData.max_ammo_add += 50
	PlayerData.reload_timer_mult += 1

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.max_ammo_add += 50
	PlayerData.reload_timer_mult += 1
