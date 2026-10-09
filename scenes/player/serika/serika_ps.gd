extends Node2D

@export var stats: Stats
@export var player: Node
@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var fire_diffuse = preload("res://scenes/debuff/fire_diffuse.tscn")

var value: Array
var diffuse_group: Array[Node]
var ps_luck: int = 70
var now_t:int
var debt_round: int = 0
var item_count: int = 0
var damage_count: float = 0
var time_damage: float = 0
var coin_gate: float = 0.0

func _ready():
	GameEvents.round_start.connect(add_debt_buff)
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	GameEvents.ability_upgrade_added.connect(player_add_item_count)
	value = [buff_layer, buff_value, buff_erase_timer]

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		coin_gate = 1.0
	elif now_t == 2:
		PlayerData.bullet_shoot_time_mult += 0.25
		PlayerData.update_player_ability()
		add_item_global_damage()
	elif now_t == 3:
		PlayerData.player_ability_changed.connect(shoot_time_damage)
		PlayerData.bullet_shoot_time_mult += 0.25
		PlayerData.update_player_ability()

func player_add_item_count(_upgrade: AbilityUpgrade, _current_upgrade: Dictionary):
	item_count += 1
	if now_t > 1:
		add_item_global_damage()

func add_item_global_damage():
	PlayerData.global_damage_mult -= damage_count
	damage_count = item_count * 0.03
	PlayerData.global_damage_mult += damage_count
	PlayerData.update_player_ability()

func shoot_time_damage():
	var target: float = max(0.0, PlayerData.bullet_shoot_time_mult - 1.0)
	if time_damage != target:
		PlayerData.bullet_damage_mult -= time_damage
		time_damage = target
		PlayerData.bullet_damage_mult += time_damage
		PlayerData.update_player_ability()

func add_debt_buff():
	if stats.coin < 0:
		if debt_round < 5:
			debt_round += 1
		value = [buff_layer, debt_round, buff_erase_timer, coin_gate]
		for i in debt_round:
			player.player_buff_manager.apply_buff(player_buff, value)
	else:
		debt_round = 0
