class_name SummonedFollower
extends Summoned

signal is_jump
signal is_jump_end

enum State {
	IDLE,
	RUNNING,
	JUMP,
}

@export var long_hair: bool = false

@onready var sprite_2d: AnimatedSprite2D = %AnimatedSprite2D
@onready var smoke: GPUParticles2D = $GPUParticles2D
@onready var jump_anim: AnimationPlayer = $jump_anim
@onready var jump_dely: Timer = $jump_dely
@onready var halo_root: Node2D = %HaloRoot
@onready var halo: Sprite2D = %Halo
@onready var graphics: Node2D = %Graphics
@onready var buff_box: HBoxContainer = %BuffBox
@onready var margin_container: MarginContainer = $MarginContainer
@onready var health_component = $HealthComponent
@onready var hurt_box = $HurtBox
@onready var hurt_anim = get_node_or_null("HurtAnim")

var crosshair_pos: Vector2
var is_jump_request: bool = false
var look_dir = null
var gun_shoot: bool = false

# ---- 联机表现同步（拥有者上报 / 远端镜像应用；单机不生效） ----
var _net_state: int = State.IDLE          # 最近一次 tick 的状态，供拥有者上报
var _net_applied_state: int = -2          # 远端镜像最近已应用的状态，避免每帧重播动画

func _ready():
	super._ready()
	jump_dely.timeout.connect(jump_start)
	GameEvents.global_time_count.connect(time_count)
	GameEvents.player_jump.connect(follow_player_jump)
	GameEvents.crosshair_position.connect(get_crosshair_pos)
	if gun != null and gun.has_signal(&"shoot_bullet"):
		gun.connect(&"shoot_bullet", _on_gun_shoot)
	if long_hair:
		GameEvents.screen_changed.connect(hair_line_changed)

func time_count():
	direction = get_direction_to_player()

func get_crosshair_pos(pos: Vector2):
	crosshair_pos = pos * get_canvas_transform()

func hair_line_changed(n: float):
	$CanvasGroup.material.set_shader_parameter("outline_width", n)

func _unhandled_input(event: InputEvent):
	if can_move:
		if event.is_action_pressed("fire"):
			gun_shoot = true
		if event.is_action_released("fire"):
			gun_shoot = false

func tick_physics(state: int, delta: float):
	if is_idle == 1:
		return
	_net_state = state
	ACCELERATION = stats.summoned_speed / stats.SPEED_TIME
	if can_move:
		match state:
			State.IDLE:
				move(0.0, delta, ACCELERATION, stats.summoned_speed)
			State.RUNNING:
				move(0.0, delta, ACCELERATION, stats.summoned_speed)
			State.JUMP:
				move(0.0, delta, ACCELERATION * 0.5, stats.summoned_speed)
	gun.position.y = sprite_2d.position.y + 9
	halo_root.position.y = sprite_2d.position.y - 17
	margin_container.position.y = sprite_2d.position.y - 40
	if long_hair:
		$GraphicsGun.scale.x = graphics.scale.x
		$GraphicsHalo.scale.x = graphics.scale.x
	if halo.position.distance_to(halo_root.position) > 0:
		halo.position = lerp(halo.position, halo_root.position, 5 * delta)
	_prune_enemy_body()
	if enemy_body.is_empty():
		set_player_lookat(crosshair_pos)
		if gun != null:
			gun.look_at(crosshair_pos)
			if gun_shoot:
				gun._shoot()
	else:
		var enemy_position = enemy_body[0].global_position
		set_player_lookat(enemy_position)
		if gun != null:
			gun.look_at(enemy_position)
			gun._shoot()

func get_next_state(state: int) -> int:
	var is_floor := sprite_2d.position.y == -17
	var is_still := velocity.x == 0 and velocity.y == 0 and is_floor
	if is_jump_request and is_floor:
		return State.JUMP
	match state:
		State.IDLE:
			if not is_still:
				return State.RUNNING
		State.RUNNING:
			if is_still:
				return State.IDLE
		State.JUMP:
			if not is_jump_request:
				return State.IDLE
	return state

func transition_state(_from: int, to: int):
	match to:
		State.IDLE:
			z_index = 0
			sprite_2d.play("idle")
			smoke.emitting = false
		State.RUNNING:
			sprite_2d.play("run")
			smoke.emitting = true
		State.JUMP:
			z_index = 3
			sprite_2d.play("jump")
			jump_anim.play("jump_anim")
			smoke.emitting = false
			GameEvents.emit_summoned_jump(global_position)
			is_jump.emit()

func set_player_lookat(dir):
	if dir != null:
		look_dir = sprite_2d.global_position + (dir * 1000)
		if dir.x > position.x:
			graphics.scale.x = 1
			halo.flip_h = false
		elif dir.x < position.x:
			graphics.scale.x = -1
			halo.flip_h = true
	else:
		look_dir = null

func get_direction_to_player():
	if player != null and position.distance_to(player.position) > 50 and is_idle == 0:
		return (player.global_position - global_position).normalized()
	return Vector2.ZERO

func jump_start():
	is_jump_request = true
	hurt_box.set_dodge(true)

func jump_end():
	is_jump_end.emit()
	is_jump_request = false
	hurt_box.set_dodge(false)

func follow_player_jump(_position: Vector2):
	var rand_time = randf_range(0.1, 0.4)
	jump_dely.wait_time = rand_time
	jump_dely.start()

func invincibility_frames():
	# 普通无敌帧：挡普通子弹/近战与接触，但不动 monitorable → 激光等来源侧检测仍命中。
	# 还原由 HurtAnim 的 .:monitoring / .:contact_invincible 轨道负责。
	hurt_box.set_invulnerable(true)
	SoundManager.play_sfx("HurtSounds3")
	if hurt_anim != null:
		hurt_anim.play("hurt_anim")


# ================= 联机表现同步（mod 回调；未装 mod 时不会被调用） =================

# 拥有者上报：用枪口朝向作为「视觉旋转」，proxy 通过已有 rotation 通道同步
func get_network_visual_rotation() -> float:
	if gun != null and is_instance_valid(gun):
		return gun.global_rotation
	return global_rotation

# 远端镜像应用：只转枪口，不跑物理/AI/开火
func apply_network_visual_rotation(rot: float, _delta: float) -> void:
	if gun != null and is_instance_valid(gun):
		gun.global_rotation = rot

# 拥有者上报：当前状态（IDLE/RUNNING/JUMP）与朝向（1 / -1）
func get_network_state() -> int:
	return _net_state

func get_network_facing() -> int:
	if graphics != null and graphics.scale.x < 0.0:
		return -1
	return 1

# 远端镜像应用：切动画 / 翻转朝向 / 跳跃表现（不移动、不开火）
func apply_network_state(state: int, facing: int) -> void:
	if facing != 0 and graphics != null and graphics.scale.x != float(facing):
		graphics.scale.x = float(facing)
		if halo != null:
			halo.flip_h = facing < 0
		if long_hair:
			$GraphicsGun.scale.x = float(facing)
			$GraphicsHalo.scale.x = float(facing)
	if state == _net_applied_state:
		return
	_net_applied_state = state
	match state:
		State.IDLE:
			z_index = 0
			if smoke != null:
				smoke.emitting = false
			sprite_2d.play("idle")
		State.RUNNING:
			if smoke != null:
				smoke.emitting = true
			sprite_2d.play("run")
		State.JUMP:
			z_index = 3
			if smoke != null:
				smoke.emitting = false
			sprite_2d.play("jump")
			jump_anim.play("jump_anim")

# 远端镜像回放开火/装填表现（由 mod _remote_summoned_action 调用；不生成子弹）
func network_play_action(action: String, dur: float = -1.0) -> void:
	if action == "shoot":
		if gun != null and gun.has_method("_shootAnim"):
			gun.call("_shootAnim", dur)

# 拥有者开火 → 通知 mod 广播（子弹本体已由 ProjectileSpawner 广播，这里只同步枪口表现）
func _on_gun_shoot(_bullet: Node) -> void:
	if is_idle == 1 or not ExtensionHooks.on_summoned_action.is_valid():
		return
	var sfx_key: String = ""
	if gun.get("sound_id") != null:
		sfx_key = str(gun.sound_id)
	var fx_scene: String = ""
	var flash = gun.get("shoot_flash")
	if flash is PackedScene and PoolManager.fx_allowed(&"muzzle_flash"):
		fx_scene = str((flash as PackedScene).resource_path)
	var fx_pos: Vector2 = gun.global_position
	var fx_rot: float = gun.global_rotation
	if gun.get("shoot") != null:
		fx_pos = (gun.get("shoot") as Node2D).global_position
	var dur: float = -1.0
	if gun.get("shoot_timer") != null:
		dur = float(gun.get("shoot_timer").wait_time)
	ExtensionHooks.notify(ExtensionHooks.on_summoned_action, [self, "shoot", sfx_key, fx_scene, fx_pos, fx_rot, dur])
