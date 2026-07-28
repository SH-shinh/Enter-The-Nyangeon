extends Node

var round_switch: bool = false
var first_round_switch: bool = false

signal first_round_add
signal round_upgrade
signal round_upgrade_end
signal round_start
signal round_end
signal round_num_changed(now_round_num: int)
signal boss_round_start
signal boss_round_end
signal fever_time_start
signal pyroxenes_pick_up
signal pyroxenes_not_enough(voice_name: String)
signal check_data
signal test_room_reset
signal test_room_button_close
signal teset_room_now_player(player_path: String)
signal coin_return_count(coins: int)

signal ui_visible(now_visible: bool)

signal global_time_count

signal camera_move(mark: Marker2D, black_frame: bool)
signal camera_reset

signal crosshair_position(position: Vector2)
signal crosshair_target(position: Vector2)

signal map_n_warring
signal map_e_warring
signal map_s_warring
signal map_w_warring

signal screen_changed(n: float)

signal add_player_upgrade(upgrade: AbilityUpgrade)

signal player_card_selected
signal player_card_id(player: String)
signal level_select_out
signal level_select_in

signal player_card_touch

signal society_card_selected(society_card: Node)

signal player_id_print(player_id: String)

signal player_coins_get(coins_value: int)
signal player_coins_cost(coins_value: int)
signal player_stats_coin_cost(coins_value: int)

signal get_player

signal spawn_start
signal spawn_restart
signal spawn_stop
signal spawn_end
signal enemy_spawn

signal shake_screen(length: int,shake_range: float,freq: float)

signal transition_start

signal ability_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary)
signal on_refresh
signal refresh_cost_count(refresh_cost: int)
signal refresh_coin_cost(coin_cost: int)
signal on_selected

signal scoreboard_select(select_name: String, type_name: String)

signal enemy_hit_position(hit_body: Node)
signal enemy_critical_hurt(enemy_body: Node)
signal enemy_body(body: Node ,bullet_body: Node) #子弹击中敌人
signal enemy_dead_position(dead_position: Vector2)
signal enemy_buff_added(enemy_buff: Buff, current_buff: Dictionary)
signal enemy_fire_hurt(enemy_body: Node)
signal enemy_explosion_hurt(enemy_body: Node)
signal enemy_poison_hurt(enemy_body: Node)
signal enemy_normal_hurt(enemy_body: Node)
signal enemy_dead_hurt_damage(hurt_damage: int)
signal enemy_dead_score(score: int)
signal enemy_coin_drops(coin: Node)
signal enemy_hurt_hp(hurt_hp: int)
signal enemy_dead_overflow_hp(overflow_hp: int)

signal player_shot_position(shot_position: Vector2, bullet_body: Node)
signal player_bullet_free_position(free_position: Vector2)
signal player_shot_critical(bullet_body: Node)
signal player_shot_not_critical(bullet_body: Node)
signal player_pick_up_coin(pick_up_position: Vector2)
signal player_is_hurt(player: Node)
signal player_ammo_reload(now_ammo: float, max_ammo: int, reload_time: float)
signal player_bullet_hit_enemy(bullet_body: Node)
signal player_buff_added(player_buff: Buff, current_buff: Dictionary)
signal player_buff_remove(buff_id: String)
signal player_critical_hit_enemy(enemy_body: Node)
signal explosion_damage(explosion_position: Vector2, explosion_range: float) #爆炸产生的位置
signal explosion_quantity(enemy_quantity: int, explosion: Node) #爆炸范围内敌人数量
signal player_bullet_kill_enemy(bullet_body: Node)
signal player_is_health(player: Node)
signal player_gun_shoot(gun: Node)
signal player_buff_clear
signal player_laser_stop
signal player_ps_upgrade(t_num: int)
signal player_combo_clear
signal aris_heat_buff
signal player_hurt_hp(hurt_hp: int)
signal player_hurt_t_hp(hurt_hp: int)
signal player_melee_hit_enemy(enemy_body: Node)
signal player_melee_critical_hit_enemy(enemy_body: Node)
signal player_bullet_explosion(position: Vector2)
signal player_jump(jump_position: Vector2)
signal player_taken_medkit(taken_position: Vector2)
signal player_revive
signal player_buff_success(buff_body: Node)
signal player_bullet_collision(bullet_body: Node)

#支援角色
signal support_card_select(support_card: SupportCard)
signal support_ex_active
signal support_ex_ready
signal support_ex_end

#召唤物
signal summoned_bullet_hit_enemy(bullet_body: Node, enemy_body: Node)
signal summoned_critical_hit_enemy(enemy_body: Node)
signal summoned_bullet_kill_enemy(bullet_body: Node)
signal summoned_bullet_free_position(free_position: Vector2)
signal summoned_shot_critical(bullet_body: Node)
signal summoned_shot_not_critical(bullet_body: Node)
signal summoned_jump(jump_position: Vector2)

signal game_over(player_dead: bool)

signal equip_shot_position(shot_position: Vector2, bullet_body: Node)
signal equip_hit_enemy(enemy_body: Node, bullet_body: Node)
signal equip_kill_enemy

signal floor_layer_group_add(floor_node: Node)

signal gamemode_conflicting(gamemode_group: Array)

func change_scene(path: String, player: String):
	var tree := get_tree()
	
	tree.change_scene_to_file(path)
	await tree.tree_changed
	
	if Transition.is_left_end_start == true:
		Transition.play_left_end()
	
	if player == "":
		return
	
	var ins = load(player).instantiate()
	
	tree.get_first_node_in_group("PlayerRoot").call_deferred("add_child",ins)
	emit_first_round_add.call_deferred()
	
	first_round_switch = false
	

func emit_scoreboard_select(select_name: String, type_name: String):
	scoreboard_select.emit(select_name, type_name)

func emit_player_id_print(player_id: String):
	player_id_print.emit(player_id)

func emit_gamemode_conflicting(gamemode_group: Array):
	gamemode_conflicting.emit(gamemode_group)

func emit_check_data():
	check_data.emit()

func emit_crosshair_position(position: Vector2):
	crosshair_position.emit(position)

func emit_crosshair_target(position: Vector2):
	crosshair_target.emit(position)

func emit_screen_changed(n: float):
	screen_changed.emit(n)

func emit_player_card_selected():
	player_card_selected.emit()

func emit_player_card_id(player: String):
	player_card_id.emit(player)

func emit_level_select_out():
	level_select_out.emit()

func emit_level_select_in():
	level_select_in.emit()

func emit_society_card_selected(society_card: Node):
	society_card_selected.emit(society_card)

func emit_round_upgrade():
	round_upgrade.emit()

func emit_round_upgrade_end():
	round_upgrade_end.emit()

func emit_boss_round_start():
	boss_round_start.emit()

func emit_boss_round_end():
	boss_round_end.emit()

func emit_pyroxenes_pick_up():
	pyroxenes_pick_up.emit()

func emit_ui_visible(now_visible: bool):
	ui_visible.emit(now_visible)

func emit_pyroxenes_not_enough(voice_name: String):
	pyroxenes_not_enough.emit(voice_name)

func emit_test_room_reset():
	test_room_reset.emit()

func emit_test_room_button_close():
	test_room_button_close.emit()

func emit_teset_room_now_player(player_path: String):
	teset_room_now_player.emit(player_path)

func emit_coin_return_count(coins: int):
	coin_return_count.emit(coins)

#屏幕触摸事件
func emit_player_card_touch():
	player_card_touch.emit()

#支援角色
func emit_support_card_select(support_card: SupportCard):
	support_card_select.emit(support_card)

func emit_support_ex_active():
	support_ex_active.emit()

func emit_support_ex_ready():
	support_ex_ready.emit()

func emit_support_ex_end():
	support_ex_end.emit()

#升级事件信号
func emit_ability_upgrade_added(upgrade:AbilityUpgrade, current_upgrade: Dictionary):
	ability_upgrade_added.emit(upgrade, current_upgrade)

func emit_on_refresh():
	on_refresh.emit()

func emit_refresh_cost_count(refresh_cost: int):
	refresh_cost_count.emit(refresh_cost)

func emit_refresh_coin_cost(coin_cost: int):
	refresh_coin_cost.emit(coin_cost)

func emit_on_selected():
	on_selected.emit()

#敌人事件信号
func emit_enemy_hit_position(hit_body: Node):
	enemy_hit_position.emit(hit_body)

func emit_enemy_critical_hurt(enemy_body: Node):
	enemy_critical_hurt.emit(enemy_body)

func emit_enemy_body(body: Node, bullet_body: Node): #子弹击中敌人
	enemy_body.emit(body,bullet_body)

func emit_enemy_dead_position(dead_position: Vector2):
	enemy_dead_position.emit(dead_position)

func emit_enemy_buff_added(enemy_buff: Buff, current_buff: Dictionary):
	enemy_buff_added.emit(enemy_buff, current_buff)

func emit_enemy_fire_hurt(enemy_body: Node):
	enemy_fire_hurt.emit(enemy_body)

func emit_enemy_explosion_hurt(enemy_body: Node):
	enemy_explosion_hurt.emit(enemy_body)

func emit_enemy_poison_hurt(enemy_body: Node):
	enemy_poison_hurt.emit(enemy_body)

func emit_enemy_normal_hurt(enemy_body: Node):
	enemy_normal_hurt.emit(enemy_body)

func emit_enemy_dead_hurt_damage(hurt_damage: int):
	enemy_dead_hurt_damage.emit(hurt_damage)

func emit_enemy_dead_score(score: int):
	enemy_dead_score.emit(score)

func emit_enemy_coin_drops(coin: Node):
	enemy_coin_drops.emit(coin)

func emit_enemy_hurt_hp(hurt_hp: int):
	enemy_hurt_hp.emit(hurt_hp)

func emit_enemy_dead_overflow_hp(overflow_hp: int):
	enemy_dead_overflow_hp.emit(overflow_hp)

#玩家事件信号
func emit_player_shot_position(shot_position: Vector2, bullet_body: Node):
	player_shot_position.emit(shot_position, bullet_body)

func emit_player_bullet_free_position(free_position: Vector2):
	player_bullet_free_position.emit(free_position)

func emit_player_shot_critical(bullet_body: Node):
	player_shot_critical.emit(bullet_body)

func emit_player_shot_not_critical(bullet_body: Node):
	player_shot_not_critical.emit(bullet_body)

func emit_player_pick_up_coin(pick_up_position: Vector2):
	player_pick_up_coin.emit(pick_up_position)

func emit_player_is_hurt(player: Node):
	player_is_hurt.emit(player)

func emit_player_ammo_reload(now_ammo: float, max_ammo: int, reload_time: float):
	player_ammo_reload.emit(now_ammo, max_ammo, reload_time)

func emit_player_bullet_hit_enemy(bullet_body: Node):
	player_bullet_hit_enemy.emit(bullet_body)

func emit_player_buff_added(player_buff: Buff, current_buff: Dictionary):
	player_buff_added.emit(player_buff, current_buff)

func emit_player_buff_remove(buff_id: String):
	player_buff_remove.emit(buff_id)

func emit_player_critical_hit_enemy(bullet_body: Node):
	player_critical_hit_enemy.emit(bullet_body)

func emit_explosion_damage(explosion_position: Vector2, explosion_range: float):
	explosion_damage.emit(explosion_position, explosion_range)

func emit_explosion_quantity(enemy_quantity: int, explosion: Node):
	explosion_quantity.emit(enemy_quantity, explosion)

func emit_player_bullet_kill_enemy(bullet_body: Node):
	player_bullet_kill_enemy.emit(bullet_body)

func emit_player_is_health(player: Node):
	player_is_health.emit(player)

func emit_player_gun_shoot(gun: Node):
	player_gun_shoot.emit(gun)

func emit_player_buff_clear():
	player_buff_clear.emit()

func emit_player_laser_stop():
	player_laser_stop.emit()

func emit_player_coins_cost(coins_value: int):
	player_coins_cost.emit(coins_value)

func emit_player_stats_coin_cost(coins_value: int):
	player_stats_coin_cost.emit(coins_value)

func emit_player_ps_upgrade(t_num: int):
	player_ps_upgrade.emit(t_num)

func emit_player_combo_clear():
	player_combo_clear.emit()

func emit_aris_heat_buff():
	aris_heat_buff.emit()

func emit_player_hurt_hp(hurt_hp: int):
	player_hurt_hp.emit(hurt_hp)

func emit_player_hurt_t_hp(hurt_hp: int):
	player_hurt_t_hp.emit(hurt_hp)

func emit_player_melee_hit_enemy(enemy_body: Node):
	player_melee_hit_enemy.emit(enemy_body)

func emit_player_melee_critical_hit_enemy(enemy_body: Node):
	player_melee_critical_hit_enemy.emit(enemy_body)

func emit_player_bullet_explosion(position: Vector2):
	player_bullet_explosion.emit(position)

func emit_player_jump(jump_position: Vector2):
	player_jump.emit(jump_position)

func emit_player_taken_medkit(taken_position: Vector2):
	player_taken_medkit.emit(taken_position)

func emit_player_revive():
	player_revive.emit()

func emit_player_buff_success(buff_body: Node):
	player_buff_success.emit(buff_body)

func emit_player_bullet_collision(bullet_body: Node):
	player_bullet_collision.emit(bullet_body)

#召唤物信号

func emit_summoned_bullet_hit_enemy(bullet_body: Node, enemy_body: Node):
	summoned_bullet_hit_enemy.emit(bullet_body, enemy_body)

func emit_summoned_critical_hit_enemy(enemy_body: Node):
	summoned_critical_hit_enemy.emit(enemy_body)

func emit_summoned_bullet_kill_enemy(bullet_body: Node):
	summoned_bullet_kill_enemy.emit(bullet_body)

func emit_summoned_bullet_free_position(free_position: Vector2):
	summoned_bullet_free_position.emit(free_position)

func emit_summoned_shot_critical(bullet_body: Node):
	summoned_shot_critical.emit(bullet_body)

func emit_summoned_shot_not_critical(bullet_body: Node):
	summoned_shot_not_critical.emit(bullet_body)

func emit_summoned_jump(jump_position: Vector2):
	summoned_jump.emit(jump_position)

#装备事件信号
func emit_equip_shot_position(shot_position: Vector2, bullet_body: Node):
	equip_shot_position.emit(shot_position, bullet_body)

func emit_equip_hit_enemy(enemy_body: Node, bullet_body: Node):
	equip_hit_enemy.emit(enemy_body, bullet_body)

func emit_equip_kill_enemy():
	equip_kill_enemy.emit()

#世界事件信号
func emit_add_player_upgrade(upgrade: AbilityUpgrade):
	add_player_upgrade.emit(upgrade)

func emit_global_time_count():
	global_time_count.emit()

func emit_first_round_add():
	if first_round_switch == false:
		first_round_switch = true
		if round_switch == true:
			round_switch = false
		first_round_add.emit()

func emit_round_num_changed(now_round_num: int):
	round_num_changed.emit(now_round_num)

func emit_round_start():
	if round_switch == false:
		round_switch = true
		round_start.emit()

func emit_round_end():
	if round_switch == true:
		round_switch = false
		round_end.emit()

func emit_fever_time_start():
	fever_time_start.emit()

func emit_transition_start():
	transition_start.emit()

func emit_spawn_start():
	spawn_start.emit()

func emit_spawn_restart():
	spawn_restart.emit()

func emit_spawn_stop():
	spawn_stop.emit()

func emit_spawn_end():
	spawn_end.emit()

func emit_enemy_spawn():
	enemy_spawn.emit()

func emit_get_player():
	get_player.emit()

func  emit_floor_layer_group_add(floor_node: Node):
	floor_layer_group_add.emit(floor_node)

func emit_game_over(player_dead: bool):
	game_over.emit(player_dead)

func emit_player_coins_get(coins_value: int):
	player_coins_get.emit(coins_value)

func emit_map_n_warring():
	map_n_warring.emit()

func emit_map_e_warring():
	map_e_warring.emit()

func emit_map_s_warring():
	map_s_warring.emit()

func emit_map_w_warring():
	map_w_warring.emit()

#镜头信号
func emit_camera_move(mark: Marker2D, black_frame: bool):
	camera_move.emit(mark, black_frame)

func emit_camera_reset():
	camera_reset.emit()

func emit_shake_screen(length: int,shake_range: float,freq: float):
	shake_screen.emit(length,shake_range,freq)
