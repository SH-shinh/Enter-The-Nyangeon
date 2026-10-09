extends Node

@export_category("生成模板")

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

@export_category("数值曲线")

@export var endless_mult: Curve
@export var endless_damage_curve: Curve
@export var endless_damage_rounds: float = 30.0 # 走完曲线所需的无尽回合数（控制软上限跨度）
@export var endless_damage_bonus: float = 1.0 # 曲线末端的攻击力最大加成（1.0 = +100%）
@export var round_damage_curve: Curve # 普通/闪击：随（按 max_round 归一化的）回合的攻击倍率曲线（替换各波次场景的 damage_mult）
@export var round_hp_curve: Curve # 普通/闪击：杂兵 HP 随回合的倍率曲线（替换各波次场景的 hp_mult）
@export var round_boss_hp_curve: Curve # 普通/闪击：Boss HP 随回合的倍率曲线（Boss 基础血量高，单独一条）
@export var hp_growth_curve: Curve # HP 难度成长的"回合指数形状"（替换 pow(level_hp, now_round/(max_round*0.5)) 的指数）
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
	for wave in ModManager.get_mod_waves():
		var scene = wave.get("scene")
		if scene == null:
			continue
		var gi := _group_index(str(wave.get("group", "lv1")))
		if gi >= 0:
			enemies_spawn_group[gi].append(scene)


func _group_index(group: String) -> int:
	if group.begins_with("lv_endless_boss"):
		return 21
	if group.begins_with("lv_endless"):
		return 20
	if group.begins_with("lv"):
		var n := int(group.substr(2))
		if n >= 1 and n <= 20:
			return n - 1
	return -1

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
		var xd = float(endless_round) / endless_damage_rounds
		endless_damage = 1 + endless_damage_curve.sample(xd) * endless_damage_bonus

func round_enemy_spawn_start():
	# 联机：客机不本地刷怪（敌人由 host 权威 + 镜像）
	if ExtensionHooks.intercept(ExtensionHooks.round_enemy_spawn_gate, []):
		return
	var num = enemies_spawn_group[group_num].size() - 1
	spawn_num = randi_range(0, num)
	if PlayerData.game_mode.has("hujiu") and group_num == 14:
		spawn_num = 1
	var spawn_ins = enemies_spawn_group[group_num][spawn_num].instantiate()
	spawn_ins.mode_mult = mode_mult
	spawn_ins.endless_hp = endless_hp
	spawn_ins.endless_boss_hp = endless_boss_hp
	spawn_ins.endless_damage = endless_damage
	spawn_ins.round_damage_curve = round_damage_curve
	spawn_ins.round_hp_curve = round_hp_curve
	spawn_ins.round_boss_hp_curve = round_boss_hp_curve
	spawn_ins.hp_growth_curve = hp_growth_curve
	spawn_ins.max_round = round_manager.max_round
	add_child(spawn_ins)
	if spawn_ins.boss_round == true:
		GameEvents.emit_boss_round_start()
	else:
		GameEvents.emit_spawn_start()

func round_enemy_spawn_end():
	GameEvents.emit_spawn_end()
