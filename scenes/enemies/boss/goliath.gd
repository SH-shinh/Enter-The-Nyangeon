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
@onready var left_arm: AnimatedSprite2D = $Graphics/LArm
@onready var right_arm: AnimatedSprite2D = $Graphics/RArm
@onready var left_explosion_fx: ExplosionAnim = $Graphics/explosion_anim
@onready var right_explosion_fx: ExplosionAnim = $Graphics/explosion_anim_R

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
@export var charge_aim_spread_deg: float = 10.0
@export var charge_bounce_spread_deg: float = 15.0
@export var charge_bounce_speed_mult: float = 0.5
@export var charge_bounce_min_wall_angle_deg: float = 30.0
@export var charge_bounce_lock_frames: int = 3
@export var shoot_to_shoot_interval: float = 0.8
@export var attack_interval: float = 1.5
@export var random_shoot_num: int = 80
@export var strafe_shoot_num: int = 50
@export var big_gun_shoot_num: int = 8
@export var big_gun_cd: int = 400
@export var charge_cd: int = 250
@export var charge_num: int = 4

var charge_speed: int = 0

var charge_active: bool = false
var _charge_ending: bool = false
var _charge_bounce_lock: int = 0
var _is_fever_time: bool = false

var can_charge: bool = false
var can_big_gun: bool = false

var charge_dir: Vector2 = Vector2.ZERO

const STEP_NONE := -1
const STEP_SHOOT := 0
const STEP_CHARGE := 1
const STEP_BIG_GUN := 2
const PHASE_60_RATIO := 0.6
const PHASE_30_RATIO := 0.3
# 乱入退场：倒放入场动画的时长基准 + 兜底余量；退场完成不能依赖 animation_finished。
const ESCAPE_ANIM: StringName = &"enter_anim"
const ESCAPE_ANIM_FALLBACK_SEC: float = 2.5
const ESCAPE_ANIM_MARGIN_SEC: float = 0.15
# 乱入 FEVER 内击杀：等待死亡动画的上限，防止信号丢失把结算永久挂起。
const DEATH_WAIT_TIMEOUT_SEC: float = 5.0

var _cycle_stage: int = 0
var _cycle_shoot_count: int = 0
var _cycle_first_template: int = -1
var _shoot_template: int = 0
var _shoot_cancel: bool = false
var _shoot_generation: int = 0
var _charge_generation: int = 0
var _big_gun_generation: int = 0
var _big_gun_cancelled: bool = false
var _next_attack_delay_override: float = -1.0
var _last_step: int = STEP_NONE
var _shooting_disabled: bool = false
var _first_hand_destroyed: bool = false
var _second_hand_destroyed: bool = false
var _left_arm_destroyed: bool = false
var _right_arm_destroyed: bool = false

@export var move_mode: int = 0

var charge_cd_time: int = 0
var charge_dir_time: int = 0
var charge_time: int = 0

var weapon_halted: bool = false
var _intruder_escaping: bool = false

func _ready():
	super._ready()
	hit_wall.connect(charge_shoot)
	GameEvents.fever_time_start.connect(enemy_fever_time)
	random_shoot_end.connect(func(): GameEvents.emit_boss_event("goliath_random_end", {}))
	strafe_shoot_end.connect(func(): GameEvents.emit_boss_event("goliath_strafe_end", {}))
	big_gun_shoot_end.connect(func(): GameEvents.emit_boss_event("goliath_big_gun_end", {}))
	hit_wall.connect(func(): GameEvents.emit_boss_event("goliath_hit_wall", {"net_id": _local_net_id()}))
	GameEvents.boss_event.connect(_on_network_boss_event)
	if stats != null and not stats.hp_changed.is_connected(_on_hp_changed):
		stats.hp_changed.connect(_on_hp_changed)
	decision_timer.wait_time = attack_interval


# 联机：把可视动画态广播给其它端；远程镜像回放（host 本机已直接播放）
var _net_visual_replaying: bool = false

func _local_net_id() -> int:
	return int(get_meta("net_id")) if has_meta("net_id") else -1

func _net_boss_visual(fn_name: String, extra: Dictionary = {}) -> void:
	if _net_visual_replaying:
		return
	var payload := {"fn": fn_name}
	var boss_net_id := _local_net_id()
	if boss_net_id >= 0:
		payload["net_id"] = boss_net_id
	payload.merge(extra, true)
	GameEvents.emit_boss_event("goliath_visual", payload)


func _on_network_boss_event(event_name: String, data: Dictionary) -> void:
	if not has_meta("network_remote_enemy"):
		return
	var local_net_id := _local_net_id()
	if event_name == "goliath_hit_wall":
		var hit_net_id = data.get("net_id", null)
		if hit_net_id != null and int(hit_net_id) != local_net_id:
			return
		mobile_3.play()
		return
	if event_name != "goliath_visual":
		return
	var target_net_id = data.get("net_id", null)
	if target_net_id != null and int(target_net_id) != local_net_id:
		return
	var fn: String = str(data.get("fn", ""))
	if fn == "":
		return
	if fn == "spawn_cannon_visual":
		_spawn_cannon_visual(data.get("pos", Vector2.ZERO))
		return
	if not has_method(fn):
		return
	_net_visual_replaying = true
	call(fn)
	_net_visual_replaying = false

func idle_state():
	reset_physics_interpolation()
	super.idle_state()
	_reset_charge_state()
	_reset_attack_state()
	_intruder_escaping = false
	boss_hp.game_ui_visible(false)
	decision_timer.stop()
	# 回池/清场时清掉演出免疫，避免免疫残留到下一次复用。
	if health_component != null:
		health_component.is_invincible = false

func active_state():
	reset_physics_interpolation()
	super.active_state()
	_reset_charge_state()
	_reset_attack_state()
	_intruder_escaping = false
	weapon_halted = false
	# 本次入场由 boss_enter_anim 重新开启免疫，先保证干净状态。
	if health_component != null:
		health_component.is_invincible = false
	boss_enter_anim()
	# 镜像不本地跑决策（AI 由 host 快照驱动）
	if not has_meta("network_remote_enemy"):
		decision_timer.wait_time = _interval_before_next_step()
		decision_timer.start()

func _reset_charge_state():
	charge_active = false
	_charge_ending = false
	_charge_bounce_lock = 0
	charge_speed = 0
	charge_dir = Vector2.ZERO
	_is_fever_time = false

func _reset_attack_state():
	_cycle_stage = 0
	_cycle_shoot_count = 0
	_cycle_first_template = -1
	_shoot_template = 0
	_shoot_cancel = false
	_shoot_generation += 1
	_charge_generation += 1
	_big_gun_generation += 1
	_big_gun_cancelled = false
	_next_attack_delay_override = -1.0
	_last_step = STEP_NONE
	_shooting_disabled = false
	_first_hand_destroyed = false
	_second_hand_destroyed = false
	_left_arm_destroyed = false
	_right_arm_destroyed = false
	if left_arm != null:
		left_arm.visible = true
	if right_arm != null:
		right_arm.visible = true
	if left_explosion_fx != null:
		left_explosion_fx.stop()
	if right_explosion_fx != null:
		right_explosion_fx.stop()

func boss_enter_anim():
	enter_anim.play("enter_anim")
	# 镜像只播动画，不做相机/暂停演出，也不设免疫（客机 HP/伤害预测由快照与 host 驱动）
	if has_meta("network_remote_enemy"):
		return
	# 入场演出期间免疫一切伤害；入场结束后按守卫条件恢复。
	if health_component != null:
		health_component.is_invincible = true
	# 乱入：不运镜、不暂停，入场动画结束后再解除免疫。
	if has_meta("boss_intruder"):
		# 乱入没有 ui_visible 事件（会连 HUD 一起藏），血条必须显式显示，
		# 不能依赖场景默认 visible 值（goliath.tscn 的 BossHP 默认 false）。
		boss_hp.game_ui_visible(true)
		_clear_enter_invincible_when_anim_done()
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
	_clear_enter_invincible_if_alive()

# 入场免疫解除：撤退/死亡接管时保持免疫（退场结束即释放节点）。
func _clear_enter_invincible_if_alive() -> void:
	if _intruder_escaping or is_idle == 1 or (stats != null and int(stats.hp) <= 0):
		return
	if health_component != null:
		health_component.is_invincible = false

# 乱入入场没有暂停外壳：等入场动画播完再解除免疫（退场倒放打断时由守卫拦下）。
func _clear_enter_invincible_when_anim_done() -> void:
	await enter_anim.animation_finished
	_clear_enter_invincible_if_alive()

func boss_death_anim():
	_net_boss_visual("boss_death_anim")
	death_anim.play("death_anim")
	# 镜像只播动画，不做相机/暂停演出
	if has_meta("network_remote_enemy"):
		return
	# 乱入：死亡动画照常播放，但不运镜、不暂停；死亡位置立即上报。
	if has_meta("boss_intruder"):
		# 乱入死亡无运镜，显式隐藏血条，避免空血条残留到 _coin_drops 释放节点。
		boss_hp.game_ui_visible(false)
		GameEvents.emit_enemy_dead_position(self.global_position)
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

# 乱入超时：倒放入场动画后消失，不运镜、不暂停、不结算奖励。
# 退场完成按入场动画长度做固定时长等待（不 await animation_finished），保证有界返回。
func boss_intruder_escape() -> void:
	if is_idle == 1 or _intruder_escaping:
		return
	_intruder_escaping = true
	weapon_halted = true
	_shoot_cancel = true
	_shoot_generation += 1
	_charge_generation += 1
	_big_gun_generation += 1
	_big_gun_cancelled = true
	_next_attack_delay_override = -1.0
	charge_active = false
	charge_speed = 0
	velocity = Vector2.ZERO
	random_shoot_timer.stop()
	strafe_shoot_timer.stop()
	big_gun_shoot_timer.stop()
	decision_timer.stop()
	if left_explosion_fx != null:
		left_explosion_fx.stop()
	if right_explosion_fx != null:
		right_explosion_fx.stop()
	_interrupt_weapons()
	collision_shape_2d.set_deferred("disabled", true)
	hurt_box_shape_2d.set_deferred("disabled", true)
	boss_hp.game_ui_visible(false)
	set_physics_process(false)
	# 退场期间免疫一切伤害：同帧命中/DOT 不能把 Boss 在退场中打死、与收尾流程竞争。
	if not has_meta("network_remote_enemy") and health_component != null:
		health_component.is_invincible = true
	enter_anim.process_mode = Node.PROCESS_MODE_ALWAYS
	enter_anim.play_backwards(ESCAPE_ANIM)
	if is_inside_tree():
		var wait_sec := ESCAPE_ANIM_FALLBACK_SEC
		var wait_anim = enter_anim.get_animation(ESCAPE_ANIM)
		if wait_anim != null:
			wait_sec = wait_anim.length
		await get_tree().create_timer(wait_sec + ESCAPE_ANIM_MARGIN_SEC, true, false, true).timeout
	PoolManager.erase_pool(pool_id)
	queue_free()

# FEVER 内击杀：等死亡动画播完再让回合结算，避免截断掉落表现。
# 等待必须有上限：动画被外部停掉/替换时裸 await 信号会让 FEVER 结算永久挂起。
func boss_intruder_wait_death() -> void:
	if death_anim == null or not is_inside_tree():
		return
	var deadline := Time.get_ticks_msec() + int(DEATH_WAIT_TIMEOUT_SEC * 1000.0)
	while is_instance_valid(death_anim) and death_anim.is_playing() \
			and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05, true, false, true).timeout
	if is_instance_valid(death_anim) and death_anim.is_playing():
		push_warning("goliath: 死亡动画等待超时，继续结算")

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
		
		var move_dir: Vector2 = charge_dir if move_mode == 1 else direction
		
		velocity.x = move_toward(velocity.x, move_dir.x * MAX_SPEED, acceleration_local * delta)
		velocity.y = move_toward(velocity.y, move_dir.y * MAX_SPEED, acceleration_local * delta)
		
		if move_dir.x > 0:
			graphics.scale.x = 1.2
		elif move_dir.x < 0:
			graphics.scale.x = -1.2
		
	else:
		velocity = Vector2.ZERO
	
	var can_check_bounce := _charge_bounce_lock <= 0
	if _charge_bounce_lock > 0:
		_charge_bounce_lock -= 1
	
	var impact_velocity := velocity
	move_and_slide()
	
	if move_mode == 1 and charge_active and stats.hp != 0 and can_check_bounce:
		var collisionResult = get_last_slide_collision()
		if collisionResult:
			_bounce_off_wall(collisionResult.get_normal(), impact_velocity)
			hit_wall.emit()

func _charge_direction_to_target(spread_deg: float) -> Vector2:
	var to_target := get_target_position() - global_position
	var angle := to_target.angle()
	if to_target.length_squared() <= 0.0001:
		angle = randf_range(-PI, PI)
	return Vector2.RIGHT.rotated(angle + deg_to_rad(randf_range(-spread_deg, spread_deg)))

func _charge_aim_direction() -> Vector2:
	return _charge_direction_to_target(charge_aim_spread_deg)

func _bounce_off_wall(collision_normal: Vector2, impact_velocity: Vector2) -> void:
	var wall_normal := collision_normal.normalized()
	if wall_normal == Vector2.ZERO:
		return
	
	var desired := _charge_direction_to_target(charge_bounce_spread_deg)
	var min_normal_dot := sin(deg_to_rad(charge_bounce_min_wall_angle_deg))
	var normal_dot := desired.dot(wall_normal)
	if normal_dot < min_normal_dot:
		var tangent := desired - wall_normal * normal_dot
		if tangent.length_squared() <= 0.0001:
			var to_target := get_target_position() - global_position
			tangent = to_target - wall_normal * to_target.dot(wall_normal)
			if tangent.length_squared() <= 0.0001:
				tangent = wall_normal.orthogonal()
				if randf() < 0.5:
					tangent = -tangent
		tangent = tangent.normalized()
		var tangent_amount := sqrt(maxf(0.0, 1.0 - min_normal_dot * min_normal_dot))
		desired = (wall_normal * min_normal_dot + tangent * tangent_amount).normalized()
	
	charge_dir = desired
	var impact_speed := impact_velocity.length()
	if impact_speed < 1.0:
		impact_speed = float(charge_speed)
	if not _is_fever_time:
		impact_speed *= charge_bounce_speed_mult
	velocity = charge_dir * impact_speed
	_charge_bounce_lock = charge_bounce_lock_frames

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
	
	if has_meta("network_remote_enemy"):
		if (_from == State.SHOOTINGREADY or _from == State.SHOOTING) and to != State.SHOOTINGREADY and to != State.SHOOTING:
			_interrupt_shoot()
		if _from == State.CHARGING and to != State.CHARGING:
			_interrupt_charge()
		if (_from == State.TURRETREADY or _from == State.TURRETSHOOT) and to != State.TURRETREADY and to != State.TURRETSHOOT and to != State.TURRETEND:
			_interrupt_big_gun()
	
	match to:
		State.IDLE:
			can_knockback = true
			move_mode = 10
			idle_state_anim()
			if not has_meta("network_remote_enemy"):
				decision_timer.wait_time = _interval_before_next_step()
				decision_timer.start()
	
		State.RUNNING:
			can_knockback = true
			running_state_anim()
		
		State.CHARGING:
			_charge_generation += 1
			var charge_gen := _charge_generation
			charge_num = 6
			can_knockback = false
			charge_active = false
			_charge_ending = false
			_charge_bounce_lock = 0
			charge_speed = 0
			velocity = Vector2.ZERO
			charge_state_anim()
			mobile_2.play()
			await body_anim.animation_finished
			if charge_gen != _charge_generation or move_mode != 1 or weapon_halted:
				return
			charge_dir = _charge_aim_direction()
			if not has_meta("network_remote_enemy"):
				static_bullet_1.bullet_timer_1.start()
				charge_shoot()
				if charge_active:
					velocity = charge_dir * charge_speed
		
		State.SHOOTINGREADY:
			can_knockback = false
			_shoot_cancel = false
			_shoot_generation += 1
			gatling_in.play()
			shoot_ready_state_anim()
		
		State.SHOOTING:
			if _shooting_disabled or _shoot_cancel:
				move_mode = 0
				return
			shoot_state_anim()
			if _shoot_template == 0:
				random_bullet()
			else:
				strafe_bullet()
			
		
		State.TURRETREADY:
			can_knockback = false
			_big_gun_cancelled = false
			turret_ready_state_anim()
		
		State.TURRETSHOOT:
			if _big_gun_cancelled:
				move_mode = 0
				return
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
	if _left_arm_destroyed:
		return
	SoundManager.play_sfx("GunSounds3")
	if not has_meta("network_remote_enemy"):
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
	if _right_arm_destroyed:
		return
	SoundManager.play_sfx("GunSounds3")
	if not has_meta("network_remote_enemy"):
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

func _shoot_cancelled() -> bool:
	return weapon_halted or _shoot_cancel or _shooting_disabled

func sync_shoot_template_random() -> void:
	_shoot_template = 0

func sync_shoot_template_strafe() -> void:
	_shoot_template = 1

func _cancel_current_shoot() -> void:
	if move_mode != 2 and move_mode != 3:
		return
	_shoot_cancel = true
	gatling_out.play()
	move_mode = 0

func _stop_shoot_if_needed(generation: int) -> bool:
	if generation != _shoot_generation:
		return true
	if _shoot_cancelled():
		_cancel_current_shoot()
		return true
	return false

func random_bullet():
	var shoot_gen := _shoot_generation
	if _stop_shoot_if_needed(shoot_gen):
		return
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
			if _stop_shoot_if_needed(shoot_gen):
				return
		random_shoot_end.emit()
		body_anim.play_backwards("shoot_ready")
		gatling_out.play()
		await body_anim.animation_finished
		if _stop_shoot_if_needed(shoot_gen):
			return
		move_mode = 0

func strafe_bullet():
	var shoot_gen := _shoot_generation
	if _stop_shoot_if_needed(shoot_gen):
		return
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
				if _stop_shoot_if_needed(shoot_gen):
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
				if _stop_shoot_if_needed(shoot_gen):
					return
		strafe_shoot_end.emit()
		body_anim.play_backwards("shoot_ready")
		gatling_out.play()
		await body_anim.animation_finished
		if _stop_shoot_if_needed(shoot_gen):
			return
		move_mode = 0

func _big_gun_interrupted(generation: int) -> bool:
	return _big_gun_cancelled or generation != _big_gun_generation or weapon_halted

func big_gun_shoot():
	MapBounds.ensure_ready()
	var big_gun_gen := _big_gun_generation
	var is_mirror := has_meta("network_remote_enemy")
	for i in big_gun_shoot_num:
		if _big_gun_interrupted(big_gun_gen):
			return
		body_anim.play("turret_shoot")
		SoundManager.play_sfx("CannonSounds1")
		await body_anim.animation_finished
		if _big_gun_interrupted(big_gun_gen):
			return
		if player != null:
			var shoot_p = get_target_position() + Vector2(randf_range(-150,150),randf_range(-150,150))
			if not is_mirror:
				shoot_p = MapBounds.nearest_inside(shoot_p, 0.0)
				var cannon_bullet_ins = PoolManager.get_pool("cannon_bullet_1")
				if cannon_bullet_ins == null or cannon_bullet_ins.is_idle == 0:
					cannon_bullet_ins = cannon_bullet.instantiate()
					get_tree().get_first_node_in_group("SELayer").add_child(cannon_bullet_ins)
				cannon_bullet_ins.setup(shoot_p, 1.2 * stats.Enemy_bullet_damage * stats.bullet_damage_mult, stats.Enemy_Knockback, 9)
				cannon_bullet_ins.shoot_bullet_num = 12
				cannon_bullet_ins.active_state()
				cannon_bullet_ins.set_meta("_coop_visual_broadcast", true)
				_net_boss_visual("spawn_cannon_visual", {"pos": shoot_p})
			big_gun_shoot_timer.start()
			await big_gun_shoot_timer.timeout
			if _big_gun_interrupted(big_gun_gen):
				return
			
	big_gun_shoot_end.emit()
	body_anim.play_backwards("turret_shoot_ready")
	leg_anim.play_backwards("turret_shoot")
	await body_anim.animation_finished
	if _big_gun_interrupted(big_gun_gen):
		return
	big_gun_cd = 400
	can_big_gun = false
	move_mode = 0

func _spawn_cannon_visual(pos) -> void:
	if not (pos is Vector2):
		return
	var layer := get_tree().get_first_node_in_group("SELayer")
	if layer == null:
		return
	var ins = cannon_bullet.instantiate()
	ins.visual_only = true
	ins.set_meta("remote_visual", true)
	layer.add_child(ins)
	ins.global_position = pos
	ins.call("active_state")

func charge_shoot():
	if is_idle == 1:
		return
	if move_mode != 1:
		return
	
	if charge_num > 0:
		mobile_3.play()
		charge_num -= 1
		charge_speed = 600
		charge_active = true
	else:
		_end_charge()

func _end_charge():
	if _charge_ending:
		return
	_charge_ending = true
	var charge_gen := _charge_generation
	charge_active = false
	_charge_bounce_lock = 0
	charge_speed = 0
	velocity = Vector2.ZERO
	body_anim.play_backwards("charge")
	leg_anim.play_backwards("charge")
	mobile_2.play()
	static_bullet_1.bullet_timer_1.stop()
	await body_anim.animation_finished
	if charge_gen != _charge_generation:
		_charge_ending = false
		return
	charge_cd = 250
	can_charge = false
	move_mode = 0
	_charge_ending = false

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
	if is_idle == 1 or _intruder_escaping:
		# 撤退优先：退场接管收尾（退场期间免疫伤害）。这里的早退是 load-bearing，
		# 防止死亡路径的 boss_death_anim / _coin_drops 在退场 await 期间自释放。
		return
	weapon_halted = true
	_shoot_cancel = true
	_shoot_generation += 1
	_charge_generation += 1
	_big_gun_generation += 1
	_big_gun_cancelled = true
	_next_attack_delay_override = -1.0
	charge_active = false
	charge_speed = 0
	velocity = Vector2.ZERO
	hurt_box_shape_2d.set_deferred("disabled", true)
	random_shoot_timer.stop()
	strafe_shoot_timer.stop()
	big_gun_shoot_timer.stop()
	decision_timer.stop()
	if left_explosion_fx != null:
		left_explosion_fx.stop()
	if right_explosion_fx != null:
		right_explosion_fx.stop()
	_interrupt_weapons()
	if not has_meta("boss_intruder"):
		GameEvents.emit_boss_round_end()
	boss_death_anim()

func _coin_drops():
	# 远端镜像：不本地生成奖励金币（host 权威同步），但保留死亡动画后自释放
	if has_meta("network_remote_enemy"):
		await death_anim.animation_finished
		queue_free()
		return
	var intruder := has_meta("boss_intruder")
	var coin_box = coins.instantiate()
	coin_box.global_position = self.global_position
	coin_box.coin_count = maxi(1, int(stats.Enemy_coin * (0.3 if intruder else 1.0)))
	coin_box.coin_quantity = 30 if intruder else 100
	get_tree().get_first_node_in_group("CoinRoot").add_child(coin_box)
	if not intruder:
		var p_box = pyroxenes.instantiate()
		p_box.global_position = self.global_position
		get_tree().get_first_node_in_group("CoinRoot").add_child(p_box)
	await death_anim.animation_finished
	coin_box.add_coin()
	PoolManager.erase_pool(pool_id)
	queue_free()
	

func enemy_fever_time():
	random_shoot_num = 120
	strafe_shoot_num = 75
	big_gun_shoot_num = 12
	_is_fever_time = true
	stats.MAX_SPEED_mult = 1.5
	stats.update_body_ability()
	leg_anim.speed_scale = 1.5
	fever_gpu.emitting = true

func _on_hp_changed() -> void:
	if has_meta("network_remote_enemy"):
		return
	if stats == null or stats.max_hp <= 0:
		return
	var ratio := float(stats.hp) / float(stats.max_hp)
	if ratio <= PHASE_30_RATIO and not _second_hand_destroyed:
		if not _first_hand_destroyed:
			_destroy_hand(randi_range(0, 1))
			_first_hand_destroyed = true
		_destroy_hand(_remaining_arm_side())
		_second_hand_destroyed = true
		_shooting_disabled = true
		_interrupt_current_attack()
	elif ratio <= PHASE_60_RATIO and not _first_hand_destroyed:
		_destroy_hand(randi_range(0, 1))
		_first_hand_destroyed = true
		_interrupt_current_attack()

func _remaining_arm_side() -> int:
	return 0 if not _left_arm_destroyed else 1

func _destroy_hand(side: int) -> void:
	_apply_arm_destroyed(side)
	_net_boss_visual("destroy_left_arm_visual" if side == 0 else "destroy_right_arm_visual")

func destroy_left_arm_visual() -> void:
	_apply_arm_destroyed(0)

func destroy_right_arm_visual() -> void:
	_apply_arm_destroyed(1)

func _apply_arm_destroyed(side: int) -> void:
	if side == 0:
		if _left_arm_destroyed:
			return
		_left_arm_destroyed = true
		if left_arm != null:
			left_arm.visible = false
		if left_explosion_fx != null:
			left_explosion_fx.play()
	else:
		if _right_arm_destroyed:
			return
		_right_arm_destroyed = true
		if right_arm != null:
			right_arm.visible = false
		if right_explosion_fx != null:
			right_explosion_fx.play()
	if _left_arm_destroyed and _right_arm_destroyed:
		_shooting_disabled = true
		_second_hand_destroyed = true
	_first_hand_destroyed = true

func get_network_boss_visual_state() -> Dictionary:
	var state := {}
	if _left_arm_destroyed:
		state["left"] = true
	if _right_arm_destroyed:
		state["right"] = true
	return state

func _apply_attack_interrupt() -> bool:
	if move_mode == 2 or move_mode == 3:
		_interrupt_shoot()
		return true
	if move_mode == 1:
		_interrupt_charge()
		return true
	if move_mode == 4 or move_mode == 5:
		_interrupt_big_gun()
		return true
	return false

func _interrupt_current_attack() -> void:
	if _apply_attack_interrupt():
		_next_attack_delay_override = attack_interval
	_net_boss_visual("interrupt_attack_visual")

func interrupt_attack_visual() -> void:
	_interrupt_shoot()
	_interrupt_charge()
	_interrupt_big_gun()

func _interrupt_shoot() -> void:
	_shoot_cancel = true
	_shoot_generation += 1
	random_shoot_timer.stop()
	strafe_shoot_timer.stop()
	gatling_in.stop()
	gatling_out.play()
	move_mode = 0

func _interrupt_charge() -> void:
	_charge_generation += 1
	charge_active = false
	_charge_ending = false
	_charge_bounce_lock = 0
	charge_speed = 0
	velocity = Vector2.ZERO
	static_bullet_1.bullet_timer_1.stop()
	mobile_2.stop()
	mobile_3.stop()
	move_mode = 0

func _interrupt_big_gun() -> void:
	_big_gun_generation += 1
	_big_gun_cancelled = true
	big_gun_shoot_timer.stop()
	move_mode = 0

func _max_shoots_for_phase() -> int:
	if _shooting_disabled or _second_hand_destroyed:
		return 0
	if _first_hand_destroyed:
		return 1
	return 2

func _can_start_shoot_step() -> bool:
	return not _shooting_disabled and _cycle_shoot_count < _max_shoots_for_phase()

func _begin_new_cycle() -> void:
	_cycle_stage = 0
	_cycle_shoot_count = 0
	_cycle_first_template = randi_range(0, 1)

func _start_shoot_step() -> void:
	var template: int
	if _max_shoots_for_phase() >= 2:
		template = _cycle_first_template if _cycle_shoot_count == 0 else 1 - _cycle_first_template
	else:
		template = randi_range(0, 1)
	_shoot_template = template
	_net_boss_visual("sync_shoot_template_random" if template == 0 else "sync_shoot_template_strafe")
	_cycle_shoot_count += 1
	_shoot_generation += 1
	_shoot_cancel = false
	_last_step = STEP_SHOOT
	move_mode = 2

func _peek_next_step() -> int:
	if _cycle_stage == 2:
		return STEP_SHOOT if _max_shoots_for_phase() > 0 else STEP_CHARGE
	if _cycle_stage == 0:
		return STEP_SHOOT if _can_start_shoot_step() else STEP_CHARGE
	return STEP_BIG_GUN

func _interval_before_next_step() -> float:
	if _next_attack_delay_override >= 0.0:
		var delay := _next_attack_delay_override
		_next_attack_delay_override = -1.0
		return delay
	if _last_step == STEP_SHOOT and _peek_next_step() == STEP_SHOOT:
		return shoot_to_shoot_interval
	return attack_interval

func _on_decision_timer_timeout() -> void:
	if is_idle == 1 or has_meta("network_remote_enemy"):
		decision_timer.stop()
		return
	if move_mode != 0 and move_mode != 10:
		return
	if _cycle_stage == 2 or _cycle_first_template < 0:
		_begin_new_cycle()
	if _cycle_stage == 0:
		if _can_start_shoot_step():
			_start_shoot_step()
			return
		_cycle_stage = 1
		_last_step = STEP_CHARGE
		move_mode = 1
		return
	if _cycle_stage == 1:
		_cycle_stage = 2
		_last_step = STEP_BIG_GUN
		_big_gun_cancelled = false
		move_mode = 4

func _on_enemy_stats_is_dead() -> void:
	on_dead.call_deferred()
