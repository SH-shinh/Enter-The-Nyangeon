extends Node

@export var round_timer: Node
@export var round_manager: Node
@export var enemy_manager: Node
@export var upgrade_manager: Node

func get_player_game_mode():
	if PlayerData.game_mode.has("blitzkrieg"):
		apply_game_mode_1()
	
	if PlayerData.game_mode.has("hujiu"):
		apply_game_mode_3()
	
	if PlayerData.game_mode.has("endless"):
		apply_game_mode_2()


func apply_game_mode_1():
	round_timer.time_mult = 0.75
	round_timer.is_game_mode_1 = true
	round_manager.max_round = 15
	upgrade_manager.round_max = 15
	enemy_manager.mode_mult = 0.95
	PlayerData.coin_mult_add += 0.5

func apply_game_mode_2():
	round_manager.is_game_mode_2 = true

func apply_game_mode_3():
	round_timer.time_mult = 1
	round_timer.is_game_mode_1 = true
	round_manager.max_round = 5
	upgrade_manager.round_max = 5
	enemy_manager.mode_mult = 0.95
	PlayerData.coin_mult_add += 3
	PlayerData.life_num_add += 2
