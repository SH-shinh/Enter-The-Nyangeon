extends EquipItem

signal dot_count_change

@onready var dot_count: float = 0:
	set(v):
		v = max(0, v)
		if dot_count == v:
			return
		dot_count = v
		dot_count_change.emit()

var bullet_count: float = 0
var player: Node

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	PlayerData.player_ability_changed.connect(value_reset)
	dot_count_change.connect(value_count)
	value_reset()

func value_reset():
	dot_count = max(0, player.stats.dot_damage - 1)

func value_count():
	PlayerData.bullet_damage_mult -= bullet_count
	bullet_count = dot_count
	PlayerData.bullet_damage_mult += bullet_count
	PlayerData.update_player_ability()
