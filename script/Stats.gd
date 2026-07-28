class_name  Stats
extends Node

signal hp_changed
signal coin_changed
signal is_hurt
signal ammo_changed
signal update_stats
signal cost_changed
signal max_ammo_changed
signal pick_up_range_changed
signal hurt_invalid_changed

@export var bullet_type: int = 0 #子弹类型
@export var luck: int = 0 #概率事件发生率
@export var critical_luck: int = 0 #暴击率
@export var luck_critical_mult: float = 1 #暴击率乘算
@export var initial_coin: int = 0 #初始硬币
@export var min_coin: int = 0 #最低硬币
@export var coin_mult: float = 1 #硬币获取率
@export var knockback_resis: int = 50 #击退抗性
@export var MAX_SPEED: int = 150 #速度
@export var SPEED_TIME: float = 0.2 #达到最大速度需要的时间
@export var max_hp: int = 100 #最大生命值
@export var heal_mult: float = 1 #治疗系数
@export_range(1, 9999) var max_ammo: int = 15 #弹匣容量
@export var max_cost: int = 50 #最大cost
@export var bullet_scale: float = 1 #子弹大小
@export var bullet_kill_time: float = 11 #子弹射程
@export var bullet_shoot_time: int = 300 #子弹射速
@export_range(50, 1600) var bullet_speed: int = 600 #子弹速度
@export var bullet_damage: int = 1 #子弹伤害
@export var bullet_recoil: int = 100 #后坐力
@export var bullet_knockback: int = 120 #击退力
@export var bullet_penetrate: int = 1 #穿透值
@export var bullet_cost: float = 1 #每次射击消耗子弹
@export var bullet_count :int = 1 #子弹数量
@export_range(0, 360) var bullet_arc :float = 0 #子弹弧度
@export var reload_timer: float = 1 #换弹时间
@export var collision_num: int = 0 #子弹反弹次数
@export var append_damage: int = 0 #追加伤害
@export var explosion_damage: float = 1 #爆炸伤害百分比
@export var explosion_range: float = 1 #爆炸范围百分比
@export var critical_damage: float = 1.5 #暴击伤害倍率
@export var dot_time: float = 1 #dot伤害持续时间加成
@export var dot_damage: float = 1 #dot伤害加成
@export var fire_dot_layer: int = 5 #火dot最大层数
@export var global_damage: float = 1 #全局伤害乘区
@export var kick_damage: int = 5 #踢击伤害
@export var pick_up_range: int = 35 #拾取半径
@export var equip_damage: float = 1 #装备伤害加成
@export var shake_mult: float = 1 #屏幕震动倍率
@export var shake_length: int = 2 #屏幕震动次数
@export var hurt_resis: int = 0 #减伤值
@export var hurt_mult: float = 1 #承伤率
@export var hurt_invalid: int = 0 #伤害无效化次数
@export var life_num: int = 0 #生命数
@export var summoned_damage: float = 1 #召唤物伤害
@export var buff_layer_mult: float = 1 #buff上限

var player_dead: bool = false
var usable_coin: int = 0

@onready var ammo: int = max_ammo:
	set(v):
		v = clamp(v, 0, max_ammo)
		if ammo == v:
			return
		ammo = v
		ammo_changed.emit()

@onready var coin: int = initial_coin:
	set(v):
		v = clamp(v, min_coin, 9999999)
		if coin == v:
			return
		if coin > v:
			GameEvents.emit_player_stats_coin_cost(coin - v)
		coin = v
		usable_coin = coin - min_coin
		coin_changed.emit()

@onready var hp: int = max_hp:
	set(v):
		v = clamp(v, 0, max_hp)
		if hp == v:
			return
		hp = v
		hp_changed.emit()
		await get_tree().create_timer(0.1).timeout
		if player_dead == false:
			if hp <= 0:
				if life_num > 0:
					PlayerData.life_num_add -= 1
					if PlayerData.game_mode.has("hujiu"):
						hp = max_hp * 0.5
						SoundManager.play_sfx("EquipSounds3")
					PlayerData.update_player_ability()
					GameEvents.emit_player_revive()
				else:
					player_dead = true
					GameEvents.emit_game_over(player_dead)

@onready var max_t_hp: int = max_hp/2

@onready var t_hp: int = 0:
	set(v):
		v = clamp(v, 0, max_t_hp)
		if t_hp == v:
			return
		t_hp = v
		hp_changed.emit()
		if t_hp <= 0:
			t_hp = 0

@onready var cost: int = 0:
	set(v):
		v = clamp(v, 0, max_cost)
		if cost == v:
			return
		cost = v
		cost_changed.emit()
