class_name  EnemyStats
extends Node

signal hp_changed
signal hp_hurt
signal is_dead

@warning_ignore("unused_signal")
signal update_stats

const BASE_KNOCKBACK_RESIS_PCT := 20 #敌人全局基础击退抗性（百分比，0-100）

@export var score: int = 1 #分数
@export var max_hp: int = 25 #最大生命值
@export var knockback_resis: int = 0 #敌人额外击退抗性（%，与全局基础叠加）
@export var penetrate_resis: int = 1 #敌人穿透抗性
@export var hurt_resis: int = 0 #敌人减伤值
@export var global_hurt_damage: float = 1.0 #敌人全局承伤系数
@export var Enemy_Knockback: int = 250 #敌人击退力
@export var Enemy_damage: int = 1 #敌人伤害
@export var Enemy_bullet_damage: int = 1 #敌人子弹伤害
@export var Enemy_coin: int = 1 #敌人掉落硬币
@export var MAX_SPEED: int = 80 #敌人速度
@export var SPEED_TIME: float = 0.1 #达到最大速度需要的时间
@export var weigth: float = 10 #重量
@export var bullet_damage_mult: float = 1 #子弹伤害乘区
@export var coin_pick: bool = false
@export var convertible: bool = true #是否可被策反
@export var is_test_target: bool = false #测试物：0 血时仍允许结算额外伤害
@export var convert_resist: int = 0 #策反抗性（百分比，0-100，100=免疫）
@export var convert_threshold: int = 100 #策反阈值
@export var convert_decay: int = 1 #策反进度衰减

var tag_set: Dictionary = {}

var base_max_hp: int = 0
var base_knockback_resis: int = 0
var base_penetrate_resis: int = 0
var base_hurt_resis: int = 0
var base_global_hurt_damage: float = 0
var base_Enemy_Knockback: int = 0
var base_Enemy_damage: int = 0
var base_Enemy_bullet_damage: int = 0
var base_Enemy_coin: int = 0
var base_MAX_SPEED: int = 0
var base_SPEED_TIME: float = 0

var max_hp_mult: float = 1
var knockback_resis_mult: float = 1
var penetrate_resis_add: int = 0
var hurt_resis_add: int = 0
var global_hurt_damage_mult: float = 1
var Enemy_Knockback_mult: float = 1
var Enemy_damage_mult: float = 1
var Enemy_bullet_damage_mult: float = 1
var Enemy_coin_mult: float = 1
var MAX_SPEED_mult: float = 1
var SPEED_TIME_mult: float = 1
var ally_damage_mult: float = 1
var ally_damage_add: int = 0

var hurt_hp = 0

var hp_change_cd: int = 0
var hurt_count: int = 0

var dead_lock: bool = false

@onready var hp: int = max_hp:
	set(v):
		
		
		hurt_hp = hp - v
		if hurt_hp > hp:
			var overflow_hurt = hurt_hp - hp
			GameEvents.emit_enemy_dead_overflow_hp(overflow_hurt)
		v = clamp(v, 0, max_hp)
		# 死亡判定必须先于任何提前 return：否则「血量已为 0 再受击」或
		# 「max_hp 被下调导致旧 hp>max_hp」时会漏发 hp_changed/is_dead，
		# 使聚合血量型 Boss（三塔）与单 Boss（goliath）血量归零却不结算。
		if v <= 0 and dead_lock == false:
			hp = v
			dead_lock = true
			hurt_hp += hurt_count
			hurt_count = 0
			hp_changed.emit()
			if hurt_hp > 0:
				hp_hurt.emit()
				GameEvents.emit_enemy_hurt_hp(hurt_hp)
			GameEvents.emit_enemy_dead_hurt_damage(hurt_hp)
			GameEvents.emit_enemy_dead_score(score)
			is_dead.emit()
			hurt_hp = 0
			return
		if hp == v:
			return
		if hp > max_hp:
			hp = v
			return
		hp = v
		
		if hp_change_cd > 0:
			#hurt_count += hurt_hp
			#hurt_hp = 0
			return
		else:
			hp_change_cd = 1
		hurt_hp += hurt_count
		hurt_count = 0
		hp_changed.emit()
		if hurt_hp > 0:
			hp_hurt.emit()
			GameEvents.emit_enemy_hurt_hp(hurt_hp)
		hurt_hp = 0
		

func _ready():
	get_body_base_ability()
	GameEvents.global_time_count.connect(time_count)

func time_count():
	if hp_change_cd > 0:
		hurt_count += hurt_hp
		hurt_hp = 0
		hp_change_cd -= 1
		if hp_change_cd <= 0:
			hurt_hp += hurt_count
			hurt_count = 0
			hp_changed.emit()
			if hurt_hp > 0:
				GameEvents.emit_enemy_hurt_hp(hurt_hp)
			hurt_hp = 0

func spawn_hp():
	dead_lock = false
	hp = max_hp

func get_body_base_ability():
	base_max_hp = max_hp
	base_knockback_resis = knockback_resis
	base_penetrate_resis = penetrate_resis
	base_hurt_resis = hurt_resis
	base_global_hurt_damage = global_hurt_damage
	base_Enemy_Knockback = Enemy_Knockback
	base_Enemy_damage = Enemy_damage
	base_Enemy_bullet_damage = Enemy_bullet_damage
	base_Enemy_coin = Enemy_coin
	base_MAX_SPEED = MAX_SPEED
	base_SPEED_TIME = SPEED_TIME
	knockback_resis = _compute_knockback_resis()

# 百分比击退抗性 = (全局基础 + 场景额外值 × 乘区) 套统一边际递减，>=100 硬免疫
func _compute_knockback_resis() -> int:
	var raw: float = BASE_KNOCKBACK_RESIS_PCT + base_knockback_resis * knockback_resis_mult
	return DamageRouter.apply_knockback_resist(raw)

func update_body_ability():
	max_hp = clamp(1, base_max_hp * max_hp_mult, 9223372036854775807)
	knockback_resis = _compute_knockback_resis()
	penetrate_resis = base_penetrate_resis + penetrate_resis_add
	hurt_resis = base_hurt_resis + hurt_resis_add
	global_hurt_damage = max(0.001, base_global_hurt_damage * global_hurt_damage_mult)
	Enemy_Knockback = int(base_Enemy_Knockback * Enemy_Knockback_mult)
	Enemy_damage = 0 if base_Enemy_damage <= 0 else max(1, ceili(base_Enemy_damage * Enemy_damage_mult))
	Enemy_bullet_damage = 0 if base_Enemy_bullet_damage <= 0 else max(1, ceili(base_Enemy_bullet_damage * Enemy_damage_mult))
	Enemy_coin = int(base_Enemy_coin * Enemy_coin_mult)
	MAX_SPEED = base_MAX_SPEED * max(0.1, MAX_SPEED_mult)
	SPEED_TIME = base_SPEED_TIME * SPEED_TIME_mult

# 移动加速度：以 base_MAX_SPEED 为下限，恶寒降速时不随之归零（否则击退后减速为 0 会一直滑行）；
# 仅当当前 MAX_SPEED 大于基准时才提高。SPEED_TIME 兜底防 0 除。
func move_acceleration() -> float:
	return maxf(float(base_MAX_SPEED), float(MAX_SPEED)) / maxf(SPEED_TIME, 0.001)
