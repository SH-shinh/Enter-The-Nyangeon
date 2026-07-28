extends Node2D

@export var stats: Stats
@export var player: Node
@export var gun_heat: Node
@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

var now_t:int
var value: Array

var heat_layer: int = 0

var player_bullet_penetrate: float

func _ready():
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	gun_heat.k_changed.connect(add_heat_critical)
	value = [buff_layer, buff_value, buff_erase_timer]


func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		PlayerData.player_ability_changed.connect(get_player_stats)
		gun_heat.k_changed.connect(add_bullet_penetrate)
	elif now_t == 2:
		buff_value = 18
		value = [buff_layer, buff_value, buff_erase_timer]
		
	elif now_t == 3:
		buff_value = 25
		value = [buff_layer, buff_value, buff_erase_timer]


func get_player_stats():
	
	player_bullet_penetrate = stats.bullet_penetrate
	player_stats_count()

func player_stats_count():
	stats.bullet_penetrate = player_bullet_penetrate + easeInCirc(gun_heat.k) * 8


func easeInCirc(x: float):
	return 1 - sqrt(1 - pow(x, 2))

func add_bullet_penetrate():
	if gun_heat.k > 0.7:
		player_stats_count()
	else:
		stats.bullet_penetrate = player_bullet_penetrate

func add_heat_critical():
	
	if gun_heat.k > 0.7 and heat_layer == 0:
		player.player_buff_manager.apply_buff(player_buff, value)
		heat_layer = 1
	
	if gun_heat.k > 0.85 and heat_layer == 1:
		player.player_buff_manager.apply_buff(player_buff, value)
		heat_layer = 2
	
	if gun_heat.k <= 0.85 and heat_layer == 2:
		GameEvents.emit_aris_heat_buff()
		heat_layer = 1
	
	if gun_heat.k <= 0.7 and heat_layer == 1:
		GameEvents.emit_aris_heat_buff()
		heat_layer = 0
