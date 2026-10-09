extends EquipItem

var hp_mult: float = 0.1

func _on_equip():
	hp_mult = 0.1
	player = get_tree().get_first_node_in_group("Player")

func _setup():
	GameEvents.enemy_damage_taken_dead.connect(add_t_hp)

func add_t_hp(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if damage_data.damage_type.has(GameTags.MELEE_DAMAGE):
		var value: int = max(1, round(player.stats.max_hp * hp_mult))
		player.stats.t_hp += value
