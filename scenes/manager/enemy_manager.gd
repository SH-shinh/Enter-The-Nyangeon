extends Node

@export var lv1: Array[PackedScene]
@export var lv2: Array[PackedScene]
@export var lv3: Array[PackedScene]
@export var lv4: Array[PackedScene]
@export var lv5: Array[PackedScene]
@export var lv6: Array[PackedScene]
@export var lv7: Array[PackedScene]
@export var lv8: Array[PackedScene]
@export var lv9: Array[PackedScene]
@export var lv10: Array[PackedScene]
@export var lv11: Array[PackedScene]
@export var lv12: Array[PackedScene]
@export var lv13: Array[PackedScene]
@export var lv14: Array[PackedScene]
@export var lv15: Array[PackedScene]
@export var lv16: Array[PackedScene]
@export var lv17: Array[PackedScene]
@export var lv18: Array[PackedScene]
@export var lv19: Array[PackedScene]
@export var lv20: Array[PackedScene]
@export var lv_endless: Array[PackedScene]
@export var lv_endless_boss: Array[PackedScene]

@export var endless_mult: Curve
@export var round_manager: Node

@onready var enemies_spawn_group: Array = [
lv1,
lv2,
lv3,
lv4,
lv5,
lv6,
lv7,
lv8,
lv9,
lv10,
lv11,
lv12,
lv13,
lv14,
lv15,
lv16,
lv17,
lv18,
lv19,
lv20,
lv_endless,
lv_endless_boss]

var group_num: int = 0
var spawn_num: int = 0
var boss_count: int = 0
var mode_mult: float = 1
var endless_round: int = 0
var endless_hp: float = 1
var endless_boss_hp: float = 1
var endless_damage: float = 1

func _ready():
	GameEvents.round_num_changed.connect(round_num_changed)
	GameEvents.round_start.connect(round_enemy_spawn_start)
	GameEvents.round_end.connect(round_enemy_spawn_end)

func round_num_changed(now_round_num: int):
	if now_round_num <= round_manager.max_round:
		var n = float(now_round_num) / float(min(20, round_manager.max_round))
		if now_round_num == 1:
			group_num = 0
		else:
			if PlayerData.game_mode.has("hujiu"):
				group_num = min(14, floor(n * 14))
			else:
				group_num = min(19, floor(n * 19))
	else:
		if PlayerData.on_endless == false:
			PlayerData.on_endless = true
		group_num = 20
		boss_count += 1
		endless_round += 1
		if boss_count >= 5:
			group_num = 21
			boss_count = 0
		var x = float(endless_round) / 10.0
		endless_hp = 1 + endless_mult.sample(x)
		endless_boss_hp = 1 + endless_mult.sample(x) * 0.2
		endless_damage = 1 + endless_mult.sample(x) * 0.2

func round_enemy_spawn_start():
	var num = enemies_spawn_group[group_num].size() - 1
	spawn_num = randi_range(0, num)
	if PlayerData.game_mode.has("hujiu") and group_num == 14:
		spawn_num = 1
	var spawn_ins = enemies_spawn_group[group_num][spawn_num].instantiate()
	spawn_ins.mode_mult = mode_mult
	spawn_ins.endless_hp = endless_hp
	spawn_ins.endless_boss_hp = endless_boss_hp
	spawn_ins.endless_damage = endless_damage
	spawn_ins.max_round = round_manager.max_round
	add_child(spawn_ins)
	if spawn_ins.boss_round == true:
		GameEvents.emit_boss_round_start()
	else:
		GameEvents.emit_spawn_start()

func round_enemy_spawn_end():
	GameEvents.emit_spawn_end()
