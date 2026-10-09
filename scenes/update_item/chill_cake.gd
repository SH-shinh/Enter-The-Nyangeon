extends EquipItem

var kill_num: int = 0

func _on_equip():
	PlayerData.max_hp_add += 5

func _setup():
	GameEvents.enemy_damage_taken_dead.connect(kill_num_count)

func kill_num_count(_final_damage: int, _damage_data: DamageData, _body_path: NodePath):
	kill_num += 1
	if kill_num >= 80:
		kill_num = 0
		add_max_hp()

func add_max_hp():
	PlayerData.max_hp_add += 1
	PlayerData.update_player_ability()
