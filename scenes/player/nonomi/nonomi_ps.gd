extends Node2D

@export var stats: Stats
@export var player: Node
@export var gun: Node
@export var coin_curve: Curve

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var shoot_timer: Timer = $ShootTimer
@onready var preheat_timer = $PreheatTimer
@onready var animation_player = $AnimationPlayer

@onready var gatling_in = $GatlingIn
@onready var gatling_out = $GatlingOut

var value: Array =[]

var now_t:int

var time_wait: int = 25
var time_num: int = 0

var bullet_num: int = 0
var coin_num: int = 0
var ps_num: int = 15
var damage_mult: float = 0.3
var max_bullet: int = 2

var is_shoot: bool = false
var on_reload: bool = false

var has_concentrated_ammo: bool = false

var ps_luck: float = 100

func _ready():
	value = [buff_layer, buff_value, buff_erase_timer]
	time_num = time_wait
	gun.can_shoot = false
	GameEvents.player_gun_shoot.connect(bullet_num_count)
	GameEvents.player_ammo_reload.connect(reload_reset)
	GameEvents.round_upgrade.connect(preheat_reset)
	GameEvents.round_start.connect(preheat_reset)
	GameEvents.enemy_body.connect(add_coin)
	PlayerData.player_ability_changed_end.connect(set_playerdata)
	player.stats.coin_changed.connect(set_playerdata)
	GameEvents.player_gun_shoot.connect(gatling_speed_buff_add)
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	GameEvents.ability_upgrade_added.connect(apply_upgrade)

func apply_upgrade(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id == "concentrated_ammo":
		has_concentrated_ammo = true
		GameEvents.ability_upgrade_added.disconnect(apply_upgrade)

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		max_bullet = 2
		GameEvents.round_start.connect(add_round_coin)
	elif now_t == 2:
		max_bullet = 3
		damage_mult = 0.4
		GameEvents.player_stats_coin_cost.connect(coin_cost_count)
	elif now_t == 3:
		max_bullet = 5
		damage_mult = 0.5

func set_playerdata():
	ps_luck = 100 * coin_curve.sample(float(stats.coin) / 500.0)
	
	if has_concentrated_ammo == false:
		var coin_v: int = player.stats.coin * damage_mult
		if PlayerData.bullet_damage_add != coin_v:
			PlayerData.bullet_damage_add = coin_v
			PlayerData.update_player_ability()
	else:
		var coin_v: int = player.stats.coin * damage_mult * (( PlayerData.base_max_ammo - 1 ) + PlayerData.max_ammo_add * PlayerData.max_ammo_mult) * 0.5
		if PlayerData.bullet_damage_add != coin_v:
			PlayerData.bullet_damage_add = coin_v
			PlayerData.update_player_ability()

func add_round_coin():
	var coin_value: int = max(1, stats.coin * 0.1)
	stats.coin += coin_value
	GameEvents.emit_player_coins_get(coin_value)
	SoundManager.play_sfx("CoinSounds")

func add_coin(_enemy_body: Node, _bullet_body: Node):
	var luck: float = randf_range(0,100)
	if luck < ps_luck:
		var coin_value: int = ceil( 1 * player.stats.coin_mult)
		stats.coin += coin_value
		GameEvents.emit_player_coins_get(coin_value)

func bullet_num_count(gun: Node):
	if now_t > 0 and shoot_timer.is_stopped() and bullet_num < max_bullet:
		shoot_timer.start()
	if gun.now_bullet_ammo <= 0 and stats.coin > 0:
		gun.now_bullet_ammo += 1
		stats.coin -= max(1, stats.coin * 0.01)
		SoundManager.play_sfx("CoinCostSounds")

func reset_count():
	shoot_timer.stop()
	PlayerData.bullet_count_add -= bullet_num
	PlayerData.bullet_arc_add -= 15 * bullet_num
	PlayerData.update_player_ability()
	bullet_num = 0

func coin_cost_count(coin_value: int):
	coin_num += coin_value
	while coin_num >= 300:
		coin_num -= 300
		PlayerData.max_ammo_add += 1
		PlayerData.update_player_ability()

func _unhandled_input(event:InputEvent ) -> void:
	
	if player.player_stop == false:
		if event.is_action_pressed("fire"):
			gatling_shoot()
		
		if event.is_action_released("fire"):
			if on_reload == false:
				gatling_out.play()
			is_shoot = false
			if now_t > 0:
				reset_count()

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

func reload_reset(_now_ammo: float, _max_ammo: int, reload_time: float):
	on_reload = true
	gatling_out.play()
	preheat_reset()
	reset_count()
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


func _on_shoot_timer_timeout() -> void:
	bullet_num += 1
	if bullet_num >= max_bullet:
		shoot_timer.stop()
	PlayerData.bullet_count_add += 1
	PlayerData.bullet_arc_add += 15
	PlayerData.update_player_ability()
