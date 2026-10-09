extends EquipItem


func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.player_hurt_hp.connect(add_t_hp)

func add_t_hp(hurt_hp: int):
	player.stats.t_hp += hurt_hp
