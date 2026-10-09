class_name  SummonedStats
extends Node

@warning_ignore("unused_signal")
signal is_hurt
signal hp_changed
signal is_dead

@export var max_hp: int = 0 #召唤物生命值
@export var summoned_damage: int = 0 #召唤物基础伤害
@export var summoned_damage_mult: float = 0 #召唤物伤害乘区
@export var summoned_max_ammo:int = 50 #召唤物弹匣数量
@export var summoned_speed: int = 150 #召唤物移动速度
@export var SPEED_TIME: float = 0.1 #达到最大速度需要的时间
@export var summoned_shoot_time: int = 250 #召唤物射速
@export var summoned_bullet_speed: int = 1000 #召唤物子弹速度
@export var summoned_knockback_resis: int = 0 #召唤物击退抗性（百分比，0-100）
@export var summoned_penetrate_resis: int = 1 #召唤物穿透抗性
@export var global_hurt_damage: float = 1.0 #召唤物伤害抗性

# ---------------- 固有等级系统配置 ----------------
# 等级/经验属于召唤物自身；任何来源（utaha 近战 / 未来道具等）都经 Summoned.add_summon_exp 喂经验。
@export var level_enabled: bool = true # 是否参与等级系统（所有召唤物默认开启）
@export var max_level: int = 0 # 等级上限，0 = 无上限
@export var level_damage_add: int = 6 # 每级提升的基础攻击（固有默认 6；来源可覆盖）
@export var level_up_exp_base: int = 3 # 首级所需经验（原 utaha 每 3 次命中升 1 级）
@export var level_exp_growth: int = 10 # 每 N 级，所需经验 +1（原 level_count>=10 逻辑）

@onready var hp: int = max_hp:
	set(v):
		v = clamp(v, 0, max_hp)
		if hp == v:
			return
		hp = v
		hp_changed.emit()
		if max_hp > 0 and hp <= 0:
			is_dead.emit()

var base_summoned_damage: int = 0 #召唤物基础伤害
var base_summoned_damage_mult: float = 0 #召唤物伤害乘区
var base_summoned_max_ammo:int = 0 #召唤物弹匣数量
var base_summoned_speed: int = 0 #召唤物移动速度
var base_summoned_shoot_time: int = 0 #召唤物射速
var base_summoned_bullet_speed: int = 0 #召唤物子弹速度
var base_global_hurt_damage: float = 1.0 #召唤物伤害抗性

var summoned_damage_add: int = 0 #伤害加算
var summoned_damage_mult_add: float = 0 #乘区加算
var summoned_max_ammo_add: int = 0 #弹匣加算
var summoned_max_ammo_mult: float = 1 #弹匣乘算
var summoned_speed_mult: float = 1 #速度乘算
var summoned_shoot_time_mult: float = 1 #射速乘算
var summoned_bullet_speed_mult: float = 1 #子弹速度乘算
var global_hurt_damage_add: float = 0 #伤害抗性加算

func _ready():
	get_body_base_ability()
	update_body_ability()
	# 属性刷新由 SummonedManager 批量驱动（避免每个召唤物各订阅一次 player_ability_changed）

func get_body_base_ability():
	base_summoned_damage = summoned_damage
	base_summoned_damage_mult = summoned_damage_mult
	base_summoned_max_ammo = summoned_max_ammo
	base_summoned_speed = summoned_speed
	base_summoned_shoot_time = summoned_shoot_time
	base_summoned_bullet_speed = summoned_bullet_speed
	base_global_hurt_damage = global_hurt_damage

func update_body_ability():
	if PlayerData.player != null:
		summoned_damage = max(0, base_summoned_damage + summoned_damage_add)
		summoned_damage_mult = max(0.1, base_summoned_damage_mult + summoned_damage_mult_add + PlayerData.player.stats.summoned_damage)
		summoned_max_ammo = max(1, (base_summoned_max_ammo + summoned_max_ammo_add) * summoned_max_ammo_mult)
		summoned_speed = max(30, base_summoned_speed * summoned_speed_mult)
		summoned_shoot_time = max(10, base_summoned_shoot_time * summoned_shoot_time_mult)
		summoned_bullet_speed = max(200, base_summoned_bullet_speed * summoned_bullet_speed_mult)
		global_hurt_damage = max(0.1, base_global_hurt_damage + global_hurt_damage_add)
