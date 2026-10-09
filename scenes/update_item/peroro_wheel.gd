extends EquipItem

func _on_equip():
	GameEvents.enemy_damage_taken.connect(melee_damage_count)

func melee_damage_count(_final_damage: int, damage_data: DamageData, body_path: NodePath):
	if damage_data.damage_type.has(GameTags.MELEE_DAMAGE):
		var body: Node = get_node_or_null(body_path)
		if body == null:
			return
		if body.stats.hp >= body.stats.max_hp:
			body.health_component.damage_multiplier += 1
