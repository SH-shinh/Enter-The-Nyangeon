extends EquipItem

var player: Node

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	PlayerData.player_ability_changed_end.connect(melee_damage_count)
	melee_damage_count()

func melee_damage_count():
	player.stats.kick_damage += player.stats.bullet_damage * 0.5
	PlayerData.emit_player_ability_changed()
