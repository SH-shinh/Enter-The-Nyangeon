extends EquipItem


var equip_luck: int = 10

func _on_equip():
	PlayerData.luck_add += 2
	equip_luck = 10

func _setup():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.enemy_damage_taken.connect(add_player_ammo)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	equip_luck += 10

func add_player_ammo(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if damage_data.is_crit == true:
		if randf_range(0,200) < (player.stats.luck + equip_luck):
			player.gun.now_bullet_ammo += 1
