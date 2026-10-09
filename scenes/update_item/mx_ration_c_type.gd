extends EquipItem

signal value_count_change

@onready var value_count: int = 0:
	set(v):
		v = max(0, v)
		if value_count == v:
			return
		value_count = v
		value_count_change.emit()
var hurt_resis_value: int = 0

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.enemy_damage_taken.connect(hurt_resis_count)
	GameEvents.player_hurt_hp.connect(hurt_remove)
	GameEvents.player_hurt_t_hp.connect(hurt_remove)
	GameEvents.round_end.connect(reset_value)
	value_count_change.connect(player_update)

func hurt_resis_count(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if damage_data.damage_type.has(GameTags.MELEE_DAMAGE):
		value_count += 1

func player_update():
	PlayerData.hurt_resis_add -= hurt_resis_value
	hurt_resis_value = value_count
	PlayerData.hurt_resis_add += hurt_resis_value
	PlayerData.update_player_ability()

func reset_value():
	value_count = 0

func hurt_remove(_hurt_hp: int):
	value_count -= value_count * 0.5
