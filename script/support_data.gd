extends Node

signal exp_changed
signal count_exp_changed
signal cost_changed
signal support_lv_up(lv: int)

@export var exp_curve: Curve
@export var support_pool: Array[SupportCard]
@export var support_ui: PackedScene
@export var null_support: SupportCard

var support_data: Dictionary

var now_support: SupportCard
var now_lv: int

var game_support: SupportCard

@onready var now_exp: int:
	set(v):
			v = max(v, 0)
			if now_exp == v:
				return
			now_exp = v
			exp_changed.emit()

@onready var now_count_exp: int:
	set(v):
			v = max(v, 0)
			if now_count_exp == v:
				return
			now_count_exp = v
			count_exp_changed.emit()

var next_exp: int
var max_exp: int
var now_count_ability: float

var ex_cost: int
@onready var now_cost: int:
	set(v):
			v = clamp(v, 0, ex_cost)
			if now_cost == v:
				return
			now_cost = v
			cost_changed.emit()

func _ready() -> void:
	exp_changed.connect(count_exp)
	count_max_exp()

func reset_game_support():
	
	if game_support != null:
		if !support_data.has(game_support.support_id):
			game_support = null_support

func game_add_support():
	if game_support.support_id == "null":
		return
	if game_support.support_pack != null:
		var ins = game_support.support_pack.instantiate()
		ins.global_position = Vector2(704, 448)
		get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)
	var ui_ins = support_ui.instantiate()
	ui_ins.support_card = game_support
	get_tree().get_first_node_in_group("GameUI").support_box.add_child(ui_ins)
	var ability_value = PlayerData.get(game_support.ability_id) + now_count_ability
	PlayerData.set(game_support.ability_id, ability_value)
	PlayerData.update_player_ability()
	now_cost = 0

func count_max_exp():
	for i in range(1, 100):
		max_exp += 200 * max(exp_curve.sample(i / 100.0), 1)

func emit_support_lv_up(lv: int):
	support_lv_up.emit(lv)

func add_new_data(support_card: SupportCard):
	var has_card = support_data.has(support_card.support_id)
	if !has_card:
		support_data[support_card.support_id] = {
			"resource": support_card,
			"LV": 1,
			"exp": 0
		}

func save_data():
	if now_support.support_id == "null":
		return
	
	var has_card = support_data.has(now_support.support_id)
	if has_card:
		support_data[now_support.support_id]["LV"] = now_lv
		support_data[now_support.support_id]["exp"] = now_exp
	Game.save_playerdata()

func load_data():
	if now_support.support_id == "null":
		return
	
	var has_card = support_data.has(now_support.support_id)
	if has_card:
		now_lv = support_data[now_support.support_id]["LV"]
		now_exp = support_data[now_support.support_id]["exp"]
		count_exp()

func get_card(support_card: SupportCard):
	now_support = support_card
	
	if now_support.support_id == "null":
		now_lv = 0
		now_exp = -1
		now_count_exp = 0
		now_count_ability = 0
		next_exp = 0
		ex_cost = 0
		return
	
	var has_card = support_data.has(now_support.support_id)
	if !has_card:
		now_lv = 0
		now_exp = -1
		now_count_exp = 0
		now_count_ability = 0
		next_exp = 0
		ex_cost = now_support.ex_cost
	else:
		load_data()
	count_exp()

func check_upgrade():
	if now_support.support_id == "null":
		return
	
	if now_count_exp >= next_exp:
		while now_count_exp >= next_exp:
			now_lv += 1
			count_exp()
			exp_changed.emit()
			if now_lv >= now_support.max_lv:
				break
		emit_support_lv_up(now_lv)
		save_data()

func level_up_voice():
	if !now_support.lv_voice.is_empty():
		var n = randi_range(0,3)
		SoundManager.play_support_voice(now_support.lv_voice[n])

func count_exp():
	if now_support.support_id == "null":
		return
	
	if now_lv > 0:
		var last_exp = 0
		if now_lv == 1:
			last_exp = 0
		else:
			for i in range(1, now_lv):
				last_exp += 200 * max(exp_curve.sample(i / 100.0), 1)
		next_exp = 200 * max(exp_curve.sample(now_lv / 100.0), 1)
		now_count_exp = now_exp - last_exp
		now_count_ability = now_support.pa_value.sample(now_lv / 100.0)
		ex_cost = now_support.ex_cost
