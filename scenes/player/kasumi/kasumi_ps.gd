extends Node2D

@export var stats: Stats
@export var player: Node
@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

var now_t:int
var value: Array

var t_cd: int = 2
var e_damage: int = 20

func _ready():
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	GameEvents.player_shot_position.connect(shoot_count)
	PlayerData.set_player.connect(set_playerdata)
	value = [buff_layer, buff_value, buff_erase_timer]

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		t_cd = 1
	elif now_t == 2:
		t_cd = 0
		buff_layer = 60
		value = [buff_layer, buff_value, buff_erase_timer]
		PlayerData.bullet_shoot_time_mult += 0.15
		PlayerData.update_player_ability()
	elif now_t == 3:
		buff_layer = 99
		value = [buff_layer, buff_value, buff_erase_timer]
		PlayerData.reload_timer_mult -= 0.3
		PlayerData.update_player_ability()

func set_playerdata():
	PlayerData.max_ammo_mult = 0.3

func shoot_count(_shot_position: Vector2, _bullet_body: Node):
	player.player_buff_manager.apply_buff(player_buff, value)
