extends EquipItem

var player: Node

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	PlayerData.max_hp_add += 20
	player.stats.hp += 20

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.max_hp_add += 20
	player.stats.hp += 20
