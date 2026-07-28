extends Node2D

signal k_changed

@export var player: Node
@export var stats: Stats
@export var heat_value: int = 5

@onready var timer = $Timer
@onready var timer_2 = $Timer2
@onready var animation_player = $AnimationPlayer
@onready var cooling_timer = $CoolingTimer

var shoot_times: float
var player_shoot_time: int
var player_recoil: int
var player_bullet_damage: int
var player_bullet_scale: float
var in_cooling: bool = false

@onready var k: float = 0:
	set(v):
		v = clamp(v, 0, 1)
		if k == v:
			return
		k = v
		k_changed.emit()

func _ready():
	GameEvents.player_gun_shoot.connect(gun_overheating_count)
	GameEvents.round_start.connect(return_to_zero)
	GameEvents.round_upgrade.connect(return_to_zero)
	PlayerData.player_ability_changed.connect(get_player_shoot_time)
	timer.timeout.connect(heat_dissipation)
	timer_2.timeout.connect(timer_start)
	cooling_timer.timeout.connect(cooling_count)
	k_changed.connect(gun_ammo_count)

func return_to_zero():
	shoot_times = 0
	k = 0
	animation_player.play("RESET")

func get_player_shoot_time():
	
	player_shoot_time = max(1, PlayerData.base_bullet_shoot_time * PlayerData.bullet_shoot_time_mult)
	player_recoil = clamp(10, PlayerData.base_bullet_recoil * PlayerData.bullet_recoil_mult, 9999)
	player_bullet_damage = clamp(1, (max(1, PlayerData.base_bullet_damage + PlayerData.bullet_damage_add) * PlayerData.bullet_damage_mult), 99999)
	player_bullet_scale = max(0.1, PlayerData.base_bullet_scale * PlayerData.bullet_scale_mult )
	player_stats_count()

func player_stats_count():
	stats.bullet_shoot_time = player_shoot_time * max(0.1, 1 - 1.5 * shoot_times * easeInCirc(k) / float(stats.max_ammo * heat_value))
	stats.bullet_recoil = player_recoil + 160 * easeInCirc(k)
	stats.bullet_damage = player_bullet_damage * damage_count(k)
	stats.bullet_scale = player_bullet_scale + easeInCirc(k)

func gun_ammo_count():
	player.gun.now_bullet_ammo = round(stats.max_ammo * ( 1 - k ))

func gun_overheating_count(gun: Node):
	timer.stop()
	
	if shoot_times < (stats.max_ammo * heat_value):
		shoot_times += 1
	else:
		shoot_times = (stats.max_ammo * heat_value)
	
	k = shoot_times / (stats.max_ammo * heat_value)
	
	player_stats_count()
	timer_2.start()
	
	if k > 0.7:
		animation_player.speed_scale = k * 10 - 6
		animation_player.play("heat_anim")
	else:
		animation_player.play("RESET")

func damage_count(x: float):
	return max(0.1, (1 - sqrt(1 - pow(x, 2))) * 3)

func easeInCirc(x: float):
	return 1 - sqrt(1 - pow(x, 2))

func timer_start():
	timer.start()

func _unhandled_input(event):
	if event.is_action_pressed("reload"):
		manual_cooling()

func manual_cooling():
	if in_cooling == false and k > 0:
		GameEvents.emit_player_ammo_reload(player.gun.now_bullet_ammo, stats.max_ammo, stats.reload_timer)
		player.gun.reload_sounds.play()
		animation_player.play("cooling_anim")
		in_cooling = true
		player.gun.can_shoot = false
		cooling_timer.start()

func cooling_count():
	if shoot_times > 0:
		shoot_times -= stats.max_ammo * 0.2
		k = shoot_times / (stats.max_ammo * heat_value)
	else:
		await get_tree().create_timer(0.2).timeout
		animation_player.play("RESET")
		in_cooling = false
		player.gun.can_shoot = true
		shoot_times = 0
		k = shoot_times / (stats.max_ammo * heat_value)
		cooling_timer.stop()

func heat_dissipation():
	if shoot_times > 0:
		shoot_times -= stats.max_ammo * 0.1
	else:
		shoot_times = 0
		timer.stop()
	k = shoot_times / (stats.max_ammo * heat_value)
	player_stats_count()
	if k > 0.7:
		animation_player.speed_scale = k * 10 - 6
		if in_cooling == false:
			animation_player.play("heat_anim")
	else:
		if in_cooling == false:
			animation_player.play("RESET")
