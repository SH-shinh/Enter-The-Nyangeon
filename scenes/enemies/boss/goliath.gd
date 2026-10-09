extends Enemy
class_name Goliath

signal random_shoot_end
signal strafe_shoot_end
signal big_gun_shoot_end

signal hit_wall

enum State {
	IDLE,
	RUNNING,
	CHARGING,
	SHOOTINGREADY,
	SHOOTING,
	TURRETREADY,
	TURRETSHOOT,
	TURRETEND,
	DEAD,
}

@onready var body = $Graphics/Body

@onready var body_anim: AnimationPlayer = $BodyAnim
@onready var leg_anim: AnimationPlayer = $LegAnim

@onready var shoot_position_R = $Graphics/RArm/Gun1/ShootPosition
@onready var shoot_position_L = $Graphics/LArm/Gun1/ShootPosition
@onready var big_gun_position: Marker2D = $Graphics/BigGun/ShootPosition
@onready var gatling_in: AudioStreamPlayer2D = $GatlingIn
@onready var gatling_out: AudioStreamPlayer2D = $GatlingOut
@onready var mobile_2: AudioStreamPlayer2D = $Mobile2
@onready var mobile_3: AudioStreamPlayer2D = $Mobile3


@onready var shoot_flash = preload("res://scenes/enemies/shoot_flash_2.tscn")
@onready var cannon_flash = preload("res://scenes/enemies/cannon_flash.tscn")
@onready var L_launcher: Node2D = $Graphics/LArm/Gun1/ShootPosition/BulletLauncher
@onready var R_launcher: Node2D = $Graphics/RArm/Gun1/ShootPosition/BulletLauncher
@onready var random_shoot_timer: Timer = $RandomShootTimer
@onready var strafe_shoot_timer: Timer = $StrafeShootTimer
@onready var big_gun_shoot_timer: Timer = $BigGunShootTimer
@onready var decision_timer: Timer = $DecisionTimer

@onready var cannon_bullet: PackedScene = preload("res://scenes/enemies/cannon_bullet.tscn")
@onready var coins: PackedScene = preload("res://scenes/item/coin_box.tscn")
@onready var pyroxenes: PackedScene = preload("res://scenes/item/pyroxenes.tscn")

@onready var static_bullet_1: Node2D = $StaticBullet1

@onready var enter_anim: AnimationPlayer = $BossEnter/EnterAnim
@onready var death_anim: AnimationPlayer = $DeathAnim/death_anim
@onready var camera_marker: Marker2D = $BossEnter/CameraMarker
@onready var boss_hp: CanvasLayer = $BossHP
@onready var fever_gpu: GPUParticles2D = $FeverGpu

@onready var buff_box: HBoxContainer = %BuffBox

@export var charge: bool = false
@export var charge_speed_mult: float = 1
@export var random_shoot_num: int = 80
@export var strafe_shoot_num: int = 50
@export var big_gun_shoot_num: int = 8
@export var big_gun_cd: int = 400
@export var charge_cd: int = 250
@export var charge_num: int = 4

var charge_speed: int = 0

var can_charge: bool = false
var can_big_gun: bool = false

var charge_dir: Vector2 = Vector2.ZERO

@export var move_mode: int = 0

var charge_cd_time: int = 0
var charge_dir_time: int = 0
var charge_time: int = 0

var weapon_halted: bool = false

func _ready():
	super._ready()
	hit_wall.connect(charge_shoot)
	GameEvents.fever_time_start.connect(enemy_fever_time)
	random_shoot_end.connect(func(): GameEvents.emit_boss_event("goliath_random_end", {}))
	strafe_shoot_end.connect(func(): GameEvents.emit_boss_event("goliath_strafe_end", {}))
	big_gun_shoot_end.connect(func(): GameEvents.emit_boss_event("goliath_big_gun_end", {}))
	hit_wall.connect(func(): GameEvents.emit_boss_event("goliath_hit_wall", {}))
	GameEvents.boss_event.connect(_on_network_boss_event)


# 联机：把可视动画态广播给其它端；远程镜像回放（host 本机已直接播放）
var _net_visual_replaying: bool = false

func _net_boss_visual(fn_name: String) -> void:
	if _net_visual_replaying:
		return
	GameEvents.emit_boss_event("goliath_visual", {"fn": fn_name})


func _on_network_boss_event(event_name: String, data: Dictionary) -> void:
	if not has_meta("network_remote_enemy"):
		return
	if event_name != "goliath_visual":
		return
	var fn: String = str(data.get("fn", ""))
	if fn == "" or not has_method(fn):
		return
	_net_visual_replaying = true
	call(fn)
	_net_visual_replaying = false

func idle_state():
	super.idle_state()
	boss_hp.game_ui_visible(false)
	decision_timer.stop()

func active_state():
	super.active_state()
	weapon_halted = false
	boss_enter_anim()
	# 镜像不本地跑决策（AI 由 host 快照驱动）
	if not has_meta("network_remote_enemy"):
		decision_timer.start()

func boss_enter_anim():
	enter_anim.play("enter_anim")
	# 镜像只播动画，不做相机/暂停演出（否则会本地 pause 整棵树）
	if has_meta("network_remote_enemy"):
		return
	GameEvents.emit_camera_move(camera_marker, true)
	GameEvents.emit_ui_visible(false)
	GameEvents.emit_pause_lock(true)
	get_tree().paused = true
	await enter_anim.animation_finished
	GameEvents.emit_camera_reset()
	GameEvents.emit_ui_visible(true)
	get_tree().paused = false
	GameEvents.emit_pause_lock(false)

func boss_death_anim():
	death_anim.play("death_anim")
	# 镜像只播动画，不做相机/暂停演出
	if has_meta("network_remote_enemy"):
		return
	GameEvents.emit_camera_move(camera_marker, true)
	GameEvents.emit_ui_visible(false)
	GameEvents.emit_pause_lock(true)
	get_tree().paused = true
	await death_anim.animation_finished
	GameEvents.emit_camera_reset()
	GameEvents.emit_ui_visible(true)
	get_tree().paused = false
	GameEvents.emit_pause_lock(false)
	GameEvents.emit_enemy_dead_position(self.global_position)

func time_count():
	super.time_count()
	if move_mode != 1:
		direction = get_direction_to_player()
	
	if big_gun_cd > 0:
		big_gun_cd -= 1
		if big_gun_cd <= 0:
			can_big_gun = true
	
	if charge_cd > 0:
		charge_cd -= 1
		if charge_cd <= 0:
			can_charge = true

func tick_physics(state: State, delta: float) -> void:
	ACCELERATION = stats.move_acceleration()
	#graphics.speed_scale = (velocity.x * velocity.x + velocity.y * velocity.y) / 6400
	apply_soft_collision()
	
	match state:
		
		State.IDLE:
			move(delta, ACCELERATION, stats.MAX_SPEED)
		State.RUNNING:
			move(delta, ACCELERATION, stats.MAX_SPEED)
		State.CHARGING:
			move(delta, ACCELERATION, charge_speed)
		State.SHOOTINGREADY:
			move(delta, ACCELERATION, stats.MAX_SPEED * 0.8)
		State.SHOOTING:
			move(delta, ACCELERATION, stats.MAX_SPEED * 1.2)
		State.TURRETREADY:
			move(delta, ACCELERATION, 0)
		State.TURRETSHOOT:
			move(delta, ACCELERATION, 0)

func move(delta: float, acceleration_local: float ,MAX_SPEED: float ) -> void:
	
	
	if stats.hp != 0:
		
		if move_mode == 1:
			var collisionResult = get_last_slide_collision()
			if collisionResult :
				direction = velocity.bounce(collisionResult.get_normal()).normalized() + (get_target_position() - global_position).normalized()
				velocity = Vector2.ZERO
				hit_wall.emit()
		
		velocity.x = move_toward(velocity.x, direction.x * MAX_SPEED, acceleration_local * delta)
		velocity.y = move_toward(velocity.y, direction.y * MAX_SPEED, acceleration_local * delta)
		
		if direction.x > 0:
			graphics.scale.x = 1.2
		elif direction.x < 0:
			graphics.scale.x = -1.2
		
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()

func get_next_state(state: State) -> State:
	
	var is_still := velocity.x == 0 and velocity.y == 0
	
	if stats.hp == 0 :
		return State.IDLE
	if move_mode == 0:
		return State.IDLE
	if move_mode == 1:
		return State.CHARGING
	if move_mode == 2:
		return State.SHOOTINGREADY
	if move_mode == 3:
		return State.SHOOTING
	if move_mode == 4:
		return State.TURRETREADY
	if move_mode == 5:
		return State.TURRETSHOOT
	if move_mode == 6:
		return State.TURRETEND
	
	
	match state:
		
		State.IDLE:
			
			if not is_still:
				return State.RUNNING
		
		State.RUNNING:
			if is_still:
				return State.IDLE
		
		State.CHARGING:
			pass
		
		State.SHOOTINGREADY:
			pass
		
		State.SHOOTING:
			pass
			
		State.TURRETREADY:
			pass
		
		State.TURRETSHOOT:
			pass
		
		State.TURRETEND:
			pass
		
	return state

func transition_state(_from:State, to: State) -> void:
	
	match to:
		State.IDLE:
			can_knockback = true
			move_mode = 10
			idle_state_anim()
			decision_timer.start()
	
		State.RUNNING:
			can_knockback = true
			running_state_anim()
		
		State.CHARGING:
			charge_num = 6
			can_knockback = false
			charge_state_anim()
			mobile_2.play()
			await body_anim.animation_finished
			direction = get_direction_to_player()
			if direction == Vector2.ZERO:
				direction = Vector2( randf_range(-1,1), randf_range(-1,1))
			static_bullet_1.bullet_timer_1.start()
			charge_shoot()
		
		State.SHOOTINGREADY:
			can_knockback = false
			gatling_in.play()
			shoot_ready_state_anim()
		
		State.SHOOTING:
			shoot_state_anim()
			var n = randi_range(0,1)
			if n == 0:
				random_bullet()
			else:
				strafe_bullet()
			
		
		State.TURRETREADY:
			can_knockback = false
			turret_ready_state_anim()
		
		State.TURRETSHOOT:
			big_gun_shoot()
		
		State.TURRETEND:
			pass
		
		State.DEAD:
			pass


func idle_state_anim():
	_net_boss_visual("idle_state_anim")
	body_play_idle()
	body_anim.play("idle")
	leg_anim.play("idle")

func running_state_anim():
	_net_boss_visual("running_state_anim")
	body_play_idle()
	leg_anim.play("run")

func shoot_ready_state_anim():
	_net_boss_visual("shoot_ready_state_anim")
	body_play_idle()
	body_anim.play("shoot_ready")

func shoot_state_anim():
	_net_boss_visual("shoot_state_anim")
	body_play_shoot()
	body_anim.play("shoot")

func charge_state_anim():
	_net_boss_visual("charge_state_anim")
	body_play_idle()
	body_anim.play("charge")
	leg_anim.play("charge")

func turret_ready_state_anim():
	_net_boss_visual("turret_ready_state_anim")
	body_play_idle()
	body_anim.play("turret_shoot_ready")
	leg_anim.play("turret_shoot")

func body_play_idle():
	body.play("idle")

func body_play_shoot():
	body.play("shoot")

func L_shoot():
	if is_idle == 1:
		return
	SoundManager.play_sfx("GunSounds3")
	L_launcher.bullet_damage = stats.Enemy_bullet_damage
	L_launcher.shoot_bullet.call_deferred()
	
	if PoolManager.fx_allowed(&"muzzle_flash"):
		var now_shoot_flash_L = PoolManager.get_pool("enemy_flash_1")
		if now_shoot_flash_L == null or now_shoot_flash_L.is_idle == 0:
			now_shoot_flash_L = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash_L)
		now_shoot_flash_L.position = shoot_position_L.global_position
		now_shoot_flash_L.rotation = shoot_position_L.global_rotation
		now_shoot_flash_L.active_state()

func R_shoot():
	if is_idle == 1:
		return
	SoundManager.play_sfx("GunSounds3")
	R_launcher.bullet_damage = stats.Enemy_bullet_damage
	R_launcher.shoot_bullet.call_deferred()
	
	if PoolManager.fx_allowed(&"muzzle_flash"):
		var now_shoot_flash_R = PoolManager.get_pool("enemy_flash_1")
		if now_shoot_flash_R == null or now_shoot_flash_R.is_idle == 0:
			now_shoot_flash_R = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash_R)
		now_shoot_flash_R.position = shoot_position_R.global_position
		now_shoot_flash_R.rotation = shoot_position_R.global_rotation
		now_shoot_flash_R.active_state()

func random_bullet():
	if player != null:
		for i in random_shoot_num:
			var player_rotation = (get_target_position() - global_position).angle()
			var L_shoot_rotation = player_rotation + randf_range(-0.5,0.5)
			var R_shoot_rotation = player_rotation + randf_range(-0.5,0.5)
			L_launcher.global_rotation = L_shoot_rotation
			R_launcher.global_rotation = R_shoot_rotation
			L_shoot()
			R_shoot()
			random_shoot_timer.start()
			await random_shoot_timer.timeout
			if weapon_halted:
				return
		random_shoot_end.emit()
		body_anim.play_backwards("shoot_ready")
		gatling_out.play()
		await body_anim.animation_finished
		move_mode = 0

func strafe_bullet():
	if player != null:
		for x in 2:
			for i in strafe_shoot_num * 0.5:
				
				var arc_rad = deg_to_rad(180)
				var increment = arc_rad / (strafe_shoot_num * 0.5 - 1)
				
				var shoot_rotation = (
					(get_target_position() - global_position).angle() +
					increment * i -
					arc_rad / 2
				)
				L_launcher.global_rotation = shoot_rotation
				R_launcher.global_rotation = shoot_rotation
				L_shoot()
				R_shoot()
				
				strafe_shoot_timer.start()
				await strafe_shoot_timer.timeout
				if weapon_halted:
					return
			for i in strafe_shoot_num * 0.5:
				
				var arc_rad = deg_to_rad(180)
				var increment = arc_rad / (strafe_shoot_num * 0.5 - 1)
				
				var shoot_rotation = (
					(get_target_position() - global_position).angle() -
					increment * i +
					arc_rad / 2
				)
				L_launcher.global_rotation = shoot_rotation
				R_launcher.global_rotation = shoot_rotation
				L_shoot()
				R_shoot()
				
				strafe_shoot_timer.start()
				await strafe_shoot_timer.timeout
				if weapon_halted:
					return
		strafe_shoot_end.emit()
		body_anim.play_backwards("shoot_ready")
		gatling_out.play()
		await body_anim.animation_finished
		move_mode = 0

func big_gun_shoot():
	
	for i in big_gun_shoot_num:
		body_anim.play("turret_shoot")
		SoundManager.play_sfx("CannonSounds1")
		await body_anim.animation_finished
		if weapon_halted:
			return
		var cannon_bullet_ins = PoolManager.get_pool("cannon_bullet_1")
		if cannon_bullet_ins == null or cannon_bullet_ins.is_idle == 0:
			cannon_bullet_ins = cannon_bullet.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(cannon_bullet_ins)
		
		if player != null:
			var shoot_p = get_target_position() + Vector2(randf_range(-150,150),randf_range(-150,150))
			cannon_bullet_ins.setup(shoot_p, 1.2 * stats.Enemy_bullet_damage * stats.bullet_damage_mult, stats.Enemy_Knockback, 9)
			cannon_bullet_ins.shoot_bullet_num = 12
			cannon_bullet_ins.active_state()
			big_gun_shoot_timer.start()
			await big_gun_shoot_timer.timeout
			if weapon_halted:
				return
			
	big_gun_shoot_end.emit()
	body_anim.play_backwards("turret_shoot_ready")
	leg_anim.play_backwards("turret_shoot")
	await body_anim.animation_finished
	big_gun_cd = 400
	can_big_gun = false
	move_mode = 0

func charge_shoot():
	if is_idle == 1:
		return
	
	if charge_num > 0:
		mobile_3.play()
		charge_num -= 1
		charge_speed = 600
	else:
		charge_speed = 0
		body_anim.play_backwards("charge")
		leg_anim.play_backwards("charge")
		mobile_2.play()
		static_bullet_1.bullet_timer_1.stop()
		await body_anim.animation_finished
		charge_cd = 250
		can_charge = false
		move_mode = 0

func add_cannon_flash():
	if PoolManager.fx_allowed(&"muzzle_flash"):
		var now_cannon_flash = PoolManager.get_pool("cannon_flash_1")
		if now_cannon_flash == null or now_cannon_flash.is_idle == 0:
			now_cannon_flash = cannon_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_cannon_flash)
		now_cannon_flash.position = big_gun_position.global_position
		now_cannon_flash.rotation = big_gun_position.global_rotation
		now_cannon_flash.active_state()

func add_shoot_flash():
	if PoolManager.fx_allowed(&"muzzle_flash"):
		var now_shoot_flash_R = PoolManager.get_pool("enemy_flash_1")
		if now_shoot_flash_R == null or now_shoot_flash_R.is_idle == 0:
			now_shoot_flash_R = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash_R)
		now_shoot_flash_R.position = shoot_position_R.global_position
		now_shoot_flash_R.rotation = shoot_position_R.global_rotation
		now_shoot_flash_R.active_state()
		
		var now_shoot_flash_L = PoolManager.get_pool("enemy_flash_1")
		if now_shoot_flash_L == null or now_shoot_flash_L.is_idle == 0:
			now_shoot_flash_L = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash_L)
		now_shoot_flash_L.position = shoot_position_L.global_position
		now_shoot_flash_L.rotation = shoot_position_L.global_rotation
		now_shoot_flash_L.active_state()

func on_dead():
	if is_idle == 1:
		return
	weapon_halted = true
	hurt_box_shape_2d.set_deferred("disabled", true)
	random_shoot_timer.stop()
	strafe_shoot_timer.stop()
	big_gun_shoot_timer.stop()
	decision_timer.stop()
	_interrupt_weapons()
	GameEvents.emit_boss_round_end()
	boss_death_anim()

func _coin_drops():
	var coin_box = coins.instantiate()
	var p_box = pyroxenes.instantiate()
	coin_box.global_position = self.global_position
	coin_box.coin_count = stats.Enemy_coin
	coin_box.coin_quantity = 100
	p_box.global_position = self.global_position
	get_tree().get_first_node_in_group("CoinRoot").add_child(coin_box)
	get_tree().get_first_node_in_group("CoinRoot").add_child(p_box)
	await death_anim.animation_finished
	coin_box.add_coin()
	PoolManager.erase_pool(pool_id)
	queue_free()
	

func enemy_fever_time():
	random_shoot_num = 120
	strafe_shoot_num = 75
	big_gun_shoot_num = 12
	stats.MAX_SPEED_mult = 1.5
	stats.update_body_ability()
	leg_anim.speed_scale = 1.5
	fever_gpu.emitting = true

func _on_decision_timer_timeout() -> void:
	
	if can_big_gun == true:
		move_mode = 4
	elif can_charge == true:
		move_mode = 1
	else:
		move_mode = 2

func _on_enemy_stats_is_dead() -> void:
	on_dead.call_deferred()
