extends PlayerPS

signal qte_end
signal perfect_reload
#38 62

@export var posion_value_min: float = -4
@export var posion_value_max: float = 4
@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var qte_bar: Node2D = $qte_bar
@onready var animation_player: AnimationPlayer = $qte_bar/AnimationPlayer
@onready var bar: Sprite2D = $qte_bar/bar
@onready var reload_timer: Timer = $ReloadTimer
@onready var shoot_timer: Timer = $ShootTimer
@onready var sprite_2d_2: Sprite2D = $qte_bar/Sprite2D2

var can_qte: bool = false
var is_perfect_reload: bool = false
var value: Array =[]
var bullet_num: int = 0

var fire_rate_value: float = 0.05
var damage_value: float = 0.03

var on_reset: bool = false

# 联机：QTE 不用全局 Engine.time_scale 慢放（会拖慢本机、房主端还会饿死网络节奏），
# 改为等比慢放 QTE 动画（qte_anim 驱动 bar 移动），世界不减速。
const LAN_QTE_ANIM_SLOW: float = 0.07

func _is_lan() -> bool:
	return ExtensionHooks.is_lan_session.is_valid() and bool(ExtensionHooks.is_lan_session.call())

func _qte_slow_begin() -> void:
	if _is_lan():
		animation_player.speed_scale = LAN_QTE_ANIM_SLOW
	else:
		GameEvents.request_slow("hina_qte", 0.07)

func _qte_slow_end() -> void:
	if _is_lan():
		if animation_player != null and is_instance_valid(animation_player):
			animation_player.speed_scale = 1.0
	else:
		GameEvents.end_slow("hina_qte")

func _ready() -> void:
	super._ready()
	qte_end.connect(qte_false)
	GameEvents.player_gun_shoot.connect(out_of_ammo_to_reload)
	GameEvents.player_ammo_reload.connect(add_reload_buff)
	value = [buff_layer, buff_value, buff_erase_timer]

func _exit_tree() -> void:
	# 场景切换/被释放时兜底解除慢放（GameEvents 侧另有 clear_slow 保护）
	GameEvents.end_slow("hina_qte")
	if animation_player != null and is_instance_valid(animation_player):
		animation_player.speed_scale = 1.0

func ps_upgrade(t_num: int):
	super.ps_upgrade(t_num)
	
	if now_t == 1:
		perfect_reload.connect(add_perfect_reload_buff)
		shoot_timer.timeout.connect(_on_shoot_timer_timeout)
		GameEvents.round_upgrade.connect(reset_count)
	elif now_t == 2:
		posion_value_min = -6
		posion_value_max = 6
		sprite_2d_2.scale.x = 0.045
		apply_distance_bullet_mod()
	elif now_t == 3:
		reset_count()
		posion_value_min = -9
		posion_value_max = 9
		sprite_2d_2.scale.x = 0.07
		fire_rate_value = 0.1
		damage_value = 0.05

func _physics_process(_delta: float) -> void:
	qte_bar.position.y = player.sprite_2d.position.y

func add_perfect_reload_buff():
	is_perfect_reload = true
	value = [buff_layer * 2, buff_value, buff_erase_timer]
	if player.player_buff_manager.current_buff.has(player_buff.id):
		player.player_buff_manager.current_buff[player_buff.id]["max_layer"] = int(buff_layer * 2 * player.stats.buff_layer_mult)
	for i in buff_layer * 2:
		player.player_buff_manager.apply_buff(player_buff, value)

func add_reload_buff(_now_ammo: float, _max_ammo: int, reload_time: float):
	if is_perfect_reload == false:
		reload_timer.wait_time = reload_time
		if reload_timer.is_stopped():
			reload_timer.start()
		await reload_timer.timeout
		value = [buff_layer, buff_value, buff_erase_timer]
		if player.player_buff_manager.current_buff.has(player_buff.id):
			player.player_buff_manager.current_buff[player_buff.id]["max_layer"] = int(buff_layer * player.stats.buff_layer_mult)
		for i in buff_layer:
			player.player_buff_manager.apply_buff(player_buff, value)

func check_qte():
	_qte_slow_end()
	if bar.position.x <= posion_value_max and bar.position.x >= posion_value_min:
		animation_player.play("true")
		fast_reload()
	else:
		reset_count()
		animation_player.play("false")
		gun.in_ammo_reload = false
		gun._ammo_reload()
	can_qte = false

func qte_false():
	_qte_slow_end()
	reset_count()
	animation_player.play("false")
	gun.in_ammo_reload = false
	gun._ammo_reload()
	can_qte = false

func emit_qte_end():
	qte_end.emit()

func fast_reload():
	perfect_reload.emit()
	PoolManager.add_text("RELOAD!", player.global_position, Color(1,1,1), 16)
	gun.reload_sounds.play()
	gun.reload_ammo()
	GameEvents.emit_player_ammo_reload(gun.now_bullet_ammo, stats.max_ammo, 0.1)
	gun.in_ammo_reload = false

func out_of_ammo_to_reload(gun_node: Node):
	if gun_node.now_bullet_ammo <= 0:
		_ammo_reload()
	if now_t > 0 and shoot_timer.is_stopped():
		shoot_timer.start()

func _ammo_reload():
	if gun.can_reload_ammo == false:
		return
	
	if gun.now_bullet_ammo != stats.max_ammo and gun.in_ammo_reload == false and can_qte == false:
		is_perfect_reload = false
		gun.in_ammo_reload = true
		_qte_slow_begin()
		SoundManager.play_sfx("ReloadSounds2")
		animation_player.play("qte_anim")
		can_qte = true

func _unhandled_input(event:InputEvent ) -> void:
	if can_qte:
		if event.is_action_pressed("reload"):
			check_qte()
	
	if now_t > 0:
		if event.is_action_released("fire"):
			reset_count()

func _on_shoot_timer_timeout() -> void:
	if on_reset == false:
		bullet_num += 1
		PlayerData.bullet_shoot_time_mult += fire_rate_value
		PlayerData.bullet_damage_mult += damage_value
		PlayerData.update_player_ability()

func reset_count():
	if on_reset == false:
		on_reset = true
		shoot_timer.stop()
		PlayerData.bullet_shoot_time_mult -= fire_rate_value * bullet_num
		PlayerData.bullet_damage_mult -= damage_value * bullet_num
		PlayerData.update_player_ability()
		bullet_num = 0
		on_reset = false

func apply_distance_bullet_mod():
	player.damage_modifier.append(func(victim: Node, actual_damage: float):
		var value = clamp(victim.global_position.distance_to(player.global_position), 100, 350)
		var distance_damage_mult = value * 0.01
		return actual_damage * distance_damage_mult
		)
