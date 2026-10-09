extends PlayerPS

signal mobu_group_changed

@export var mobu_pack: PackedScene

var mobu_group: Array[Node]
var ps_luck: int = 70
var revive_hp: float = 0.5
var now_rate_value:float = 0
var summoned_damage_count: float = 0

func _ready():
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	GameEvents.round_start.connect(round_start_add_mobu)
	GameEvents.player_revive.connect(player_revive_hp)

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		PlayerData.summoned_damage_add += 0.25
		PlayerData.update_player_ability()
		now_rate_value += 0.3
		revive_hp = 0.7
		update_mobu_fire_rate(now_rate_value)
	elif now_t == 2:
		PlayerData.summoned_damage_add += 0.25
		PlayerData.update_player_ability()
		now_rate_value += 0.3
		revive_hp = 1
		update_mobu_fire_rate(now_rate_value)
	elif now_t == 3:
		PlayerData.summoned_damage_add += 0.25
		PlayerData.update_player_ability()
		mobu_group_changed.connect(update_player_summoned_damage)
		update_player_summoned_damage()

func update_player_summoned_damage():
	PlayerData.summoned_damage_add -= summoned_damage_count
	summoned_damage_count = mobu_group.size() * 0.25
	PlayerData.summoned_damage_add += summoned_damage_count
	PlayerData.update_player_ability()

func update_mobu_fire_rate(rate_value: int):
	if !mobu_group.is_empty():
		for i in mobu_group:
			i.stats.summoned_shoot_time_mult += now_rate_value
			i.stats.update_body_ability()

func round_start_rand_mobu_position():
	var center_position: Vector2 = Vector2(704, 448)
	if !mobu_group.is_empty():
		for i in mobu_group:
			i.global_position = Vector2(randf_range(-50,50), randf_range(-50,50)) + center_position

func player_revive_hp():
	PlayerData.add_player_revive(revive_hp)
	SoundManager.play_sfx("PowerUp1")
	if !mobu_group.is_empty():
		mobu_group[0].idle_state()
		mobu_group.remove_at(0)
		mobu_group_changed.emit()

func round_start_add_mobu():
	var ins = mobu_pack.instantiate()
	ins.global_position = Vector2(704, 448)
	ins.stats.summoned_shoot_time_mult += now_rate_value
	get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)
	mobu_group.append(ins)
	mobu_group_changed.emit()
	PlayerData.life_num_add += 1
	PlayerData.update_player_ability()
	round_start_rand_mobu_position()
	if !GameEvents.deal_damage_to_player.is_connected(player.health_component.take_damage):
		GameEvents.deal_damage_to_player.connect(player.health_component.take_damage)
