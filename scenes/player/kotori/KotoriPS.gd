extends Node2D

@export var stats: Stats
@export var player: Node
@export var gun: Node

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var preheat_timer = $PreheatTimer
@onready var animation_player = $AnimationPlayer

@onready var gatling_in = $GatlingIn
@onready var gatling_out = $GatlingOut

var value: Array =[]

var now_t:int

var time_wait: int = 25
var time_num: int = 0

var shoot_num: int = 0
var ps_num: int = 15
var damage_mult: float = 0.1

var is_shoot: bool = false
var on_reload: bool = false

func _ready():
	value = [buff_layer, buff_value, buff_erase_timer]
	time_num = time_wait
	gun.can_shoot = false
	GameEvents.player_shot_position.connect(shoot_count)
	GameEvents.player_ammo_reload.connect(reload_reset)
	GameEvents.round_upgrade.connect(preheat_reset)
	GameEvents.round_start.connect(preheat_reset)
	GameEvents.enemy_body.connect(add_max_hp_damage)
	PlayerData.set_player.connect(set_playerdata)
	GameEvents.player_gun_shoot.connect(gatling_speed_buff_add)
	GameEvents.player_ps_upgrade.connect(ps_upgrade)

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		PlayerData.bullet_count_add += 1
		PlayerData.bullet_arc_add += 20
		damage_mult = 0.2
		PlayerData.max_t_hp_mult += 0.5
		PlayerData.update_player_ability()
	elif now_t == 2:
		PlayerData.bullet_count_add += 1
		PlayerData.bullet_arc_add += 20
		damage_mult = 0.4
		PlayerData.max_t_hp_mult += 0.25
		PlayerData.update_player_ability()
	elif now_t == 3:
		damage_mult = 0.8
		PlayerData.max_t_hp_mult += 0.25
		PlayerData.update_player_ability()

func set_playerdata():
	PlayerData.bullet_damage_mult = 0.5

func add_max_hp_damage(enemy_body: Node, bullet_body: Node):
	enemy_body.hurt_damage += max(1, (stats.max_hp + stats.t_hp) * damage_mult)

func shoot_count(_shot_position: Vector2, _bullet_body: Node):
	shoot_num += 1
	if shoot_num >= ps_num:
		stats.t_hp += 1
		shoot_num = 0

func _unhandled_input(event:InputEvent ) -> void:
	
	if player.player_stop == false:
		if event.is_action_pressed("fire"):
			gatling_shoot()
		
		if event.is_action_released("fire"):
			if on_reload == false:
				gatling_out.play()
			is_shoot = false

func gatling_speed_buff_add(_gun: Node):
	player.player_buff_manager.apply_buff(player_buff, value)

func gatling_shoot():
	is_shoot = true
	if on_reload == true:
		return
	if gun.can_shoot == false:
		gatling_in.play()
	
	if preheat_timer.is_stopped():
		preheat_timer.start()
	else:
		if gun.can_shoot == true:
			time_num = 0

func reload_reset(now_ammo: float, max_ammo: int, reload_time: float):
	on_reload = true
	gatling_out.play()
	preheat_reset()
	await get_tree().create_timer(reload_time).timeout
	on_reload = false
	if is_shoot == true:
		gatling_shoot()

func preheat_reset():
	time_num = time_wait
	gun.can_shoot = false
	preheat_timer.stop()
	animation_player.speed_scale = 10 - 0.36 * time_num
	if animation_player.is_playing():
		animation_player.play("RESET")

func _on_preheat_timer_timeout():
	if is_shoot == true:
		if !animation_player.is_playing():
			animation_player.play("new_animation")
		else:
			animation_player.speed_scale = 10 - 0.36 * time_num
		time_num -= 1
		if time_num <= 0:
			time_num = 0
			if animation_player.is_playing():
				animation_player.play("RESET")
			gun.can_shoot = true
	else:
		if !animation_player.is_playing():
			animation_player.play("new_animation")
		else:
			animation_player.speed_scale = 10 - 0.36 * time_num
		time_num += 1
		animation_player.speed_scale = 10 - 0.36 * time_num
		if time_num >= time_wait:
			if animation_player.is_playing():
				animation_player.play("RESET")
			time_num = time_wait
			gun.can_shoot = false
			preheat_timer.stop()
