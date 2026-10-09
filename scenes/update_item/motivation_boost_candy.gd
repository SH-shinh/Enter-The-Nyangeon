extends EquipItem


var cd_time: int = 0
var delay_time: int = 0

var t_hp_count: int = 0

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	pass

func _setup():
	GameEvents.enemy_damage_taken.connect(add_t_hp)
	GameEvents.global_time_count.connect(time_count)

func time_count():
	if cd_time > 0:
		cd_time -= 1
	if delay_time > 0:
		delay_time -= 1
		if delay_time <= 0:
			player.stats.t_hp += t_hp_count
			t_hp_count = 0

func add_t_hp(final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if damage_data.damage_type.has(GameTags.POISON_DAMAGE):
		if cd_time <= 0:
			t_hp_count += ceil(final_damage * 0.03)
			cd_time = 1
		if delay_time <= 0:
			delay_time = 6
