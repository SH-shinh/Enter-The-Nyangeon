class_name  SummonedStats
extends Node

signal is_hurt

@export var summoned_damage: int = 0 #召唤物基础伤害
@export var summoned_damage_mult: float = 0 #召唤物伤害乘区
@export var summoned_max_ammo:int = 50 #召唤物弹匣数量
@export var summoned_speed: int = 150 #召唤物移动速度
@export var SPEED_TIME: float = 0.1 #达到最大速度需要的时间
@export var summoned_shoot_time: int = 250 #召唤物射速
@export var summoned_bullet_speed: int = 1000 #召唤物子弹速度
@export var summoned_knockback_resis: int = 0 #召唤物击退抗性
@export var summoned_penetrate_resis: int = 1 #召唤物穿透抗性

var base_summoned_damage: int = 0 #召唤物基础伤害
var base_summoned_damage_mult: float = 0 #召唤物伤害乘区
var base_summoned_max_ammo:int = 0 #召唤物弹匣数量
var base_summoned_speed: int = 0 #召唤物移动速度
var base_summoned_shoot_time: int = 0 #召唤物射速
var base_summoned_bullet_speed: int = 0 #召唤物子弹速度

var summoned_damage_add: int = 0 #伤害加算
var summoned_damage_mult_add: float = 0 #乘区加算
var summoned_max_ammo_add: int = 0 #弹匣加算
var summoned_max_ammo_mult: float = 1 #弹匣乘算
var summoned_speed_mult: float = 1 #速度乘算
var summoned_shoot_time_mult: float = 1 #射速乘算
var summoned_bullet_speed_mult: float = 1 #子弹速度乘算

func _ready():
	get_body_base_ability()
	update_body_ability()
	PlayerData.player_ability_changed.connect(update_body_ability)

func get_body_base_ability():
	base_summoned_damage = summoned_damage
	base_summoned_damage_mult = summoned_damage_mult
	base_summoned_max_ammo = summoned_max_ammo
	base_summoned_speed = summoned_speed
	base_summoned_shoot_time = summoned_shoot_time
	base_summoned_bullet_speed = summoned_bullet_speed

func update_body_ability():
	if PlayerData.player != null:
		summoned_damage = max(0, base_summoned_damage + summoned_damage_add)
		summoned_damage_mult = max(0.1, base_summoned_damage_mult + summoned_damage_mult_add + PlayerData.player.stats.summoned_damage)
		summoned_max_ammo = max(1, (base_summoned_max_ammo + summoned_max_ammo_add) * summoned_max_ammo_mult)
		summoned_speed = max(30, base_summoned_speed * summoned_speed_mult)
		summoned_shoot_time = max(10, base_summoned_shoot_time * summoned_shoot_time_mult)
		summoned_bullet_speed = max(200, base_summoned_bullet_speed * summoned_bullet_speed_mult)
