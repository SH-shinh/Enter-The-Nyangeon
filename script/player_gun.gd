extends Node2D
class_name PlayerGun

@export var stats: Stats
@export var bullet: PackedScene
@export var bullet_pool_id: String = "player_bullet"
@export var shoot_flash: PackedScene = preload("res://scenes/weapon/Unique_Idea/shoot_flash.tscn")
@export var parabola: bool = false
@export var can_reload_ammo: bool = true
@export var single_load: bool = false
@export var random_bullet: bool = false
@export var random_sounds: bool = false
@export var semi_auto: bool = false
@export var is_clip: bool = false
## 开火是否抛壳（每扳机一颗，不按弹丸数）。非枪械类武器可在场景里关掉。
@export var eject_casings: bool = true
@export var casing_scene: PackedScene = preload("res://scenes/effects/bullet_casing.tscn")

@onready var fire_sounds = $FireSounds
@onready var reload_sounds = $ReloadSounds
@onready var reload_anim = $ReloadAnim
@onready var sprite_2d = $Sprite2D
@onready var shoot_position = $ShootPosition
@onready var shoot_timer = $ShootTimer
@onready var ammo_reload_timer = $AmmoReloadTimer
@onready var fire_anim = $FireAnim

var player: Node
var now_bullet_ammo: float
var in_ammo_reload:bool = false
var can_shoot:bool = true
var is_shoot:bool = false

var sustained_fire_damage_decay_per_shot: float = 0.0
var sustained_fire_damage_decay_cap: float = 0.0
var sustained_fire_decay_reset_time: float = 1.0
var _shot_streak: int = 0
var _time_since_last_shot: float = 0.0
var _pending_damage_mult: float = 1.0

var crosshair_pos: Vector2

func _ready():
	now_bullet_ammo = stats.max_ammo
	GameEvents.crosshair_position.connect(get_crosshair_pos)
	GameEvents.get_player.connect(get_player)
	ammo_reload_timer.timeout.connect(reload_end)
	get_player()

func get_player():
	player = get_tree().get_first_node_in_group("Player")

func get_crosshair_pos(crosshair_position: Vector2):
	crosshair_pos = crosshair_position * get_canvas_transform()

func _physics_process(delta: float):
	if now_bullet_ammo > stats.max_ammo:
		now_bullet_ammo = stats.max_ammo
	if sustained_fire_damage_decay_per_shot > 0.0:
		_time_since_last_shot += delta
		if _time_since_last_shot >= sustained_fire_decay_reset_time:
			_shot_streak = 0
	if stats.bullet_shoot_time > 0:
		shoot_timer.wait_time = float(60.0 / stats.bullet_shoot_time )
	# 眩晕（stun buff）：本帧不开火；枪的朝向由 StateMachine 早退一并停住。
	if player != null and player.has_method("is_stunned") and player.is_stunned():
		return
	if player != null and is_shoot == true and shoot_timer.time_left <= 0 and ammo_reload_timer.time_left <= 0 and can_shoot == true :
		_shoot()
		if semi_auto == true:
			is_shoot = false

func  _ammo_reload():
	
	if can_reload_ammo == false:
		return
	
	reset_sustained_fire()

	if stats.reload_timer > 0:
		ammo_reload_timer.wait_time = stats.reload_timer
	
	
	if now_bullet_ammo != stats.max_ammo and in_ammo_reload == false :
		
		if single_load == false:
			in_ammo_reload = true
			shoot_timer.stop()
			GameEvents.emit_player_ammo_reload(now_bullet_ammo, stats.max_ammo, stats.reload_timer)
			ammo_reload_timer.start()
			reload_sounds.play()
			reload_anim.speed_scale = 1/ammo_reload_timer.wait_time
			reload_anim.play("reload")
			ExtensionHooks.notify_named("on_player_reload", [self, "reload", reload_anim.speed_scale])
	
		else:
			if is_clip == true and now_bullet_ammo <= 0:
				in_ammo_reload = true
				shoot_timer.stop()
				GameEvents.emit_player_ammo_reload(now_bullet_ammo, stats.max_ammo, stats.reload_timer)
				ammo_reload_timer.start()
				reload_sounds.play()
				reload_anim.speed_scale = 1/ammo_reload_timer.wait_time
				reload_anim.play("reload")
				ExtensionHooks.notify_named("on_player_reload", [self, "reload", reload_anim.speed_scale])
			else:
				in_ammo_reload = true
				shoot_timer.stop()
				ammo_reload_timer.start()
				reload_anim.speed_scale = 1/ammo_reload_timer.wait_time
				reload_anim.play("reload_2_start")
				ExtensionHooks.notify_named("on_player_reload", [self, "reload_2_start", reload_anim.speed_scale])
				await reload_anim.animation_finished
				while now_bullet_ammo < stats.max_ammo:
					ammo_reload_timer.start()
					reload_sounds.play()
					reload_anim.play("reload_2")
					GameEvents.emit_player_ammo_reload(now_bullet_ammo, stats.max_ammo, stats.reload_timer)
					await reload_anim.animation_finished
					if is_shoot == true:
						break
				
				reload_anim.play("reload_2_end")
	

func reload_end():
	in_ammo_reload = false

func reload_ammo():
	reset_sustained_fire()
	if single_load == false:
		now_bullet_ammo = stats.max_ammo
	else:
		if is_clip == true and now_bullet_ammo <= 0:
			now_bullet_ammo = stats.max_ammo
		else:
			now_bullet_ammo += 1

func _shoot() -> void:
	if now_bullet_ammo <= 0 and can_reload_ammo == true and stats.bullet_cost != 0:
		_ammo_reload()
		return
	
	if ammo_reload_timer.time_left > 0:
		return
	
	shoot_timer.start()
	GameEvents.emit_shake_screen( stats.shake_length, 15 * stats.shake_mult, 0.025 )
	_pending_damage_mult = _current_sustained_fire_damage_mult()
	_shoot_bullet()
	_eject_casing()
	if PoolManager.fx_allowed(&"muzzle_flash"):
		var now_shoot_flash = PoolManager.get_pool("player_flash")
		if now_shoot_flash == null or now_shoot_flash.is_idle == 0:
			now_shoot_flash = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash)
		now_shoot_flash.position = shoot_position.global_position
		now_shoot_flash.rotation = global_rotation
		now_shoot_flash.active_state()
		# 联机：每次开火广播枪口闪光（池复用时 child_entered_tree 不再触发）
		ExtensionHooks.notify_named("on_visual_activated", [now_shoot_flash])
	if random_sounds == true:
		fire_sounds.pitch_scale = randf_range(0.8, 1.2)
	fire_sounds.play()
	_shootAnim()
	now_bullet_ammo = consume_ammo(now_bullet_ammo, stats.bullet_cost)
	_shot_streak += 1
	_time_since_last_shot = 0.0
	GameEvents.emit_player_gun_shoot(self)

func _shoot_bullet():
	var direction: Vector2 = global_position \
			.direction_to(crosshair_pos) \
			.normalized()
	if stats.bullet_count == 1:
		ProjectileSpawner.spawn_core(
			bullet, bullet_pool_id, "BulletRoot", player, Faction.PLAYER_SIDE,
			shoot_position.global_position, direction.angle(), Vector2.ZERO,
			true, false, true,
			Callable(self, "_configure_bullet"),
			Callable(self, "_emit_player_shot_pre")
		)
	else:
		var arc_rad = deg_to_rad(stats.bullet_arc)
		if random_bullet == true:
			arc_rad *= randf_range(0.8,1.2)
		var increment = arc_rad / (stats.bullet_count - 1)
		for i in stats.bullet_count:
			ProjectileSpawner.spawn_core(
				bullet, bullet_pool_id, "BulletRoot", player, Faction.PLAYER_SIDE,
				shoot_position.global_position, direction.angle() + increment * i - arc_rad / 2, Vector2.ZERO,
				true, false, true,
				Callable(self, "_configure_bullet"),
				Callable(self, "_emit_player_shot_pre")
			)

## 抛壳：每扳机一颗（不按弹丸数）。生成点就是 Gun 自身位置，离地高度取 Gun 的 y。
## **不消耗子弹（`bullet_cost <= 0`，UI 显示 "∞"）的武器不抛壳**——没有弹壳概念。
## 纯本地表现：不参与伤害/碰撞，不做联机同步。挂在 FloorLayer（在 YSort 之前），
## 飞行期把 z_index 抬到世界层之上（不会被角色挡住），落地静止后 z 归 0 回到地板层；
## 数量上限由 PoolManager.IDLE_LIMITS["casing"] 给，满额时环状复用最旧弹壳。
func _eject_casing() -> void:
	if eject_casings == false:
		return
	# 读运行时值：PlayerData 会按 base_bullet_cost * bullet_cost_mult 重算，不能读场景快照。
	# 0 消耗的实例见 scenes/player/aris/aris.tscn（HUD 显示 "∞"）。
	if stats == null or stats.bullet_cost <= 0.0:
		return
	if PoolManager.fx_allowed(&"casing") == false:
		return
	var floor_layer := get_tree().get_first_node_in_group("FloorLayer")
	if floor_layer == null:
		return
	var aim: Vector2 = global_position.direction_to(crosshair_pos).normalized()
	if aim == Vector2.ZERO:
		aim = Vector2.RIGHT
	# 抛壳口高度 = Gun 的 y：player.gd 每帧维护 gun.position.y = sprite_2d.position.y + gun_root(9)，
	# 地面时约 -8（离地 8px），跳跃时 sprite_2d.position.y 更负 → Gun 更高，弹壳也从更高处抛出。
	var ground: Vector2 = global_position
	var start_height: float = 0.0
	if player is Node2D:
		var ground_y: float = (player as Node2D).global_position.y
		start_height = maxf(0.0, ground_y - global_position.y)
		ground = Vector2(global_position.x, ground_y)
	var casing = PoolManager.get_pool("casing")
	if casing == null:
		casing = casing_scene.instantiate()
		floor_layer.add_child(casing)
	casing.active_state(ground, aim, start_height)

func _configure_bullet(node: Node) -> void:
	var direction: Vector2 = global_position \
			.direction_to(crosshair_pos) \
			.normalized()
	shoot_position.rotation = direction.angle()
	node.set_meta("player_damage_mult", _pending_damage_mult)
	if random_bullet == true:
		node.speed = stats.bullet_speed * randf_range(0.7,1)
	else:
		node.speed = stats.bullet_speed
	node.penetrate = stats.bullet_penetrate
	node.collision_num = stats.collision_num
	node.kill_time = stats.bullet_kill_time * 10
	var recoil_speed: Vector2 = direction * (stats.bullet_recoil / stats.bullet_count)
	player.velocity -= recoil_speed
	if parabola == true:
		var length = shoot_position.global_position.distance_to(crosshair_pos)
		node.mouse_length = length

func _emit_player_shot_pre(node: Node) -> void:
	GameEvents.emit_player_shot_position(shoot_position.global_position, node)

func _shootAnim():
	var anim_speed:float = max(1, 0.3 / shoot_timer.wait_time)
	fire_anim.play("RESET")
	fire_anim.play("fire", -1, anim_speed, false)

func reset_sustained_fire() -> void:
	_shot_streak = 0
	_time_since_last_shot = 0.0

func _current_sustained_fire_damage_mult() -> float:
	return sustained_fire_damage_mult(_shot_streak, sustained_fire_damage_decay_per_shot, sustained_fire_damage_decay_cap)

static func sustained_fire_damage_mult(streak: int, per_shot: float, cap: float) -> float:
	if per_shot <= 0.0:
		return 1.0
	return maxf(1.0 - cap, 1.0 - per_shot * float(streak))

static func consume_ammo(current: float, cost: float) -> float:
	return maxf(0.0, current - cost)
