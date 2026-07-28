extends Node2D

@export var stats: Stats
@export var player: Node
@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@export var player_buff_2: Buff
@export var buff_layer_2: int
@export var buff_value_2: float
@export var buff_erase_timer_2: float

@export var player_buff_3: Buff
@export var buff_layer_3: int
@export var buff_value_3: float
@export var buff_erase_timer_3: float

@onready var combo_timer = $ComboTimer
@onready var shoot_timer = $ShootTimer
@onready var combo_text = $CanvasLayer/combo_text

var ps_luck: int = 70
var now_t:int
var value: Array
var value_2: Array
var value_3: Array

var combo_num: int = 0
var gun_shoot_count: int = 0

func _ready():
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	GameEvents.explosion_quantity.connect(combo_count)
	GameEvents.round_start.connect(combo_clear)
	GameEvents.round_upgrade.connect(combo_clear)
	GameEvents.game_over.connect(combo_remove)
	combo_timer.timeout.connect(combo_clear)
	shoot_timer.timeout.connect(combo_clear)
	value_3 = [buff_layer_3, buff_value_3, buff_erase_timer_3]
	combo_text.idle_state()

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		PlayerData.critical_damage_add += 0.25
		PlayerData.update_player_ability()
		PlayerData.player_ability_changed_end.connect(critical_damage_count)
	elif now_t == 2:
		PlayerData.critical_damage_add += 0.25
		PlayerData.update_player_ability()
		value = [buff_layer, buff_value, buff_erase_timer]
		GameEvents.player_ammo_reload.connect(reload_ammo_buff)
	elif now_t == 3:
		PlayerData.critical_damage_add += 0.25
		PlayerData.update_player_ability()
		buff_value_3 = 0.2
		value_3 = [buff_layer_3, buff_value_3, buff_erase_timer_3]

func reload_ammo_buff(_now_ammo: float, _max_ammo: int, reload_time: float):
	await get_tree().create_timer(reload_time).timeout
	player.player_buff_manager.apply_buff(player_buff, value)

func critical_damage_count():
	stats.bullet_shoot_time *= max(1, (1 + PlayerData.critical_damage_add) * 0.2)
	PlayerData.emit_player_ability_changed()

func combo_count(enemy_size: int, explosion: Node):
	if explosion.is_player_bullet == true:
		combo_num += 1
		if combo_num > 999:
			combo_text.combo_num("UZQUEEN!")
			combo_text.play_max_anim()
		else:
			combo_text.combo_num(str(combo_num))
		combo_timer.start()
		player.player_buff_manager.apply_buff(player_buff_3, value_3)

func combo_remove(player_dead: bool):
	combo_clear()

func combo_clear():
	GameEvents.emit_player_combo_clear()
	combo_num = 0
	gun_shoot_count = 0
	combo_text.idle_state()
