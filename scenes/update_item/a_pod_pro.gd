extends EquipItem

var kill_num: int

func _on_equip():
	GameEvents.enemy_damage_taken_dead.connect(equip_kill_count)

func equip_kill_count(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if damage_data.source_type.has(GameTags.EQUIP):
		kill_num += 1
		if kill_num >= 50:
			PlayerData.equip_damage_mult += 0.03
			PlayerData.update_player_ability()
			kill_num = 0
