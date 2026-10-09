extends EquipItem

var player_luck: int = 0
var luck_add: int = 0

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	luck_count()

func _setup():
	PlayerData.player_ability_changed_end.connect(luck_count)

func luck_count():
	luck_add = max(0, round(player.stats.luck * 0.3))
	player.stats.critical_luck += luck_add
	PlayerData.emit_player_ability_changed()
