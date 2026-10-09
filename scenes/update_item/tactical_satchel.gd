extends EquipItem


func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	PlayerData.hurt_mult_mult *= 0.92
	PlayerData.max_hp_add += 24
	player.stats.hp += 24

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.hurt_mult_mult *= 0.92
	PlayerData.max_hp_add += 24
	player.stats.hp += 24
