extends EquipItem


func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	PlayerData.hurt_resis_mult += 1
	PlayerData.MAX_SPEED_value = player.stats.MAX_SPEED
