extends Node

signal enemy_clear
signal coin_clear
signal bullet_clear
signal backlayer_clear
signal item_clear
signal player_portal

var refresh_cost: int = 1
var refresh_cost_add: float = 0
var round_mult: float = 1
var now_refresh_cost: int = 0
var selected_cost_add: int = 0
var now_round_num: int = 0
var refresh_cost_add_num:float = 0

var is_game_over: bool = false

var max_round: int = 20
var is_game_mode_2: bool = false

var on_round_end: bool = false

var selected_mult: float = 6

func _ready():
	GameEvents.round_upgrade_end.connect(_on_round_start)
	GameEvents.round_end.connect(_on_round_end)
	GameEvents.on_refresh.connect(refresh_cost_count)
	GameEvents.on_selected.connect(selected_cost_count)
	GameEvents.round_num_changed.connect(round_num_count)
	GameEvents.game_over.connect(is_game_over_true)

func is_game_over_true(player_dead: bool):
	is_game_over = true

func round_num_count(round_num: int):
	now_round_num = round_num

func emit_enemy_clear():
	enemy_clear.emit()

func emit_coin_clear():
	coin_clear.emit()

func emit_bullet_clear():
	bullet_clear.emit()

func emit_backlayer_clear():
	backlayer_clear.emit()

func emit_item_clear():
	item_clear.emit()

func emit_player_portal():
	player_portal.emit()

func selected_cost_count():
	now_refresh_cost += selected_mult * round_mult + now_refresh_cost
	refresh_cost_add_num += 0.2
	GameEvents.emit_refresh_cost_count(now_refresh_cost)

func refresh_cost_count():
	now_refresh_cost += refresh_cost * refresh_cost_add
	refresh_cost_add_num += 0.2
	refresh_cost_add = refresh_cost_add_num * refresh_cost_add_num * refresh_cost_add_num
	GameEvents.emit_refresh_cost_count(now_refresh_cost)

func first_round_start():
	
	on_round_end = false
	
	selected_mult = (float(max_round) / 20.0) * 6
	refresh_cost = 2
	now_refresh_cost = refresh_cost
	refresh_cost_add = 0
	refresh_cost_add_num = 0
	selected_cost_add = 0
	
	FloatingPool.empty_pool()
	GameEvents.emit_get_player()
	emit_player_portal()
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	GameEvents.emit_round_start()

func _on_round_start():
	
	on_round_end = false
	
	round_mult += 0.2
	refresh_cost = float(pow(round_mult,1)) + float(pow(round_mult,1.5)) * float(pow(round_mult,1.5))
	now_refresh_cost = refresh_cost
	refresh_cost_add = 0
	refresh_cost_add_num = 0
	selected_cost_add = 0
	
	await get_tree().create_timer(0.1).timeout
	Transition.play_left_start()
	await Transition.left_end_start
	get_tree().paused = false
	Transition.play_left_end()
	emit_player_portal()
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED_HIDDEN
	GameEvents.emit_round_start()

func _on_round_end():
	
	if on_round_end == true:
		return
	
	on_round_end = true
	
	emit_enemy_clear()
	emit_coin_clear()
	await get_tree().create_timer(1.0).timeout
	FloatingPool.empty_pool()
	
	if is_game_over == true:
		return
	
	if now_round_num >= max_round and !PlayerData.game_mode.has("endless"):
		var player_dead = false
		GameEvents.emit_game_over(player_dead)
	else:
		
		Transition.play_left_start()
		await Transition.left_end_start
		Transition.play_left_end()
		emit_bullet_clear()
		emit_backlayer_clear()
		emit_item_clear()
		emit_player_portal()
		GameEvents.emit_round_upgrade()
		GameEvents.emit_player_buff_clear()
		get_tree().paused = true
