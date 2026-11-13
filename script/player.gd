extends CharacterBody2D
class_name Player

enum State {
	IDLE,
	RUNNING,
	JUMP,
	FLY,
	FALL,
}

@export var player_card: PlayerCard
@export var ps_card: PSCard
@export var stats: Stats
@export var player_color: Color
@export var long_hair: bool = false
@export var mortar: bool = false
@export var hat_position: float = 13
@export var halo_root_position: float = 17
@export var gun_root: float = 9
## 是否允许近战踢击。hare 用右键切换形态，需关闭以免同键触发。
@export var allow_kick: bool = true
@export var base_pitch_scale: float = 1.0

var ACCELERATION: float

const JUMP_SPEED:int = 10

var gravity := ProjectSettings.get("physics/2d/default_gravity") as float
var is_jump_request:bool = false
var look_dir = null
var is_run_request:bool = false
var hurt_dir: Vector2 = Vector2.ZERO
var hurt_knockback: int = 0
var hurt_damage: int = 0

var can_move:bool = true
var can_jump:bool = true
var can_control: bool = true
var player_stop:bool = false

# 联机倒地状态：由 mod 经 ExtensionHooks.player_death_gate 接管后调用 set_downed_state()。
var is_downed: bool = false

var can_knockback: bool = true

## 受击无敌帧闪烁：由代码逐帧切 visible，时长跟随 InvincibleFrame（0.5s / 0.1s / 道具延长）。
## 旧方案是场景内 "Invincible frame" 动画（固定 0.5s 的 visible 关键帧），时长变化时会拖尾，
## 因此改为代码控制；动画保留在场景里但不再播放（见 _start_invincible_flash 的 stop）。
const INVINCIBLE_FLASH_INTERVAL: float = 0.075
var _flash_nodes: Array[Node] = []
var _flash_accum: float = 0.0
var _flash_tick: int = 0
var _flashing: bool = false

var crosshair_pos: Vector2

var on_hit: bool = false

var is_buff_hurt: bool = false

var damage_modifier: Array[Callable] = []
var damage_dealt: Array[Callable] = []
var damage_types: Array[String] = []
var flags: Array[String] = []

@onready var gun = $%Gun
@onready var kick = $Kick
@onready var smoke = $GPUParticles2D
@onready var halo = $%Halo
@onready var graphics = $%Graphics
@onready var sprite_2d: AnimatedSprite2D = $%AnimatedSprite2D
@onready var jump_timer = $JumpTimer
@onready var fly_timer = $FlyTimer
@onready var jump_cd_timer = $JumpCDTimer
@onready var halo_root = $%HaloRoot
@onready var jump_sounds = $JumpSounds
@onready var run_sounds = $RunSounds
@onready var run_sounds_timer = $RunSoundsTimer
@onready var invincible_frame = $InvincibleFrame
@onready var invincible_frame_anim = $AnimationPlayer
@onready var on_hit_sounds = $OnHitSounds
@onready var coin_sounds = $CoinSounds
@onready var pause_screen = $CanvasLayer/PauseScreen
@onready var jump_cd_bar = $JumpCDBar
@onready var camera_2d = $Camera2D
@onready var kick_anim = $AnimationPlayer2
@onready var collision_shape_2d = $PickBox/CollisionShape2D
@onready var player_buff_manager = $PlayerBuffManager
@onready var game_ui = $GameUI
@onready var hurt_box = $HurtBox
@onready var hurtbox_shape: CollisionShape2D = $HurtBox/HurtboxShape
@onready var hit_shape: CollisionShape2D = $CollisionShape2D
@onready var floating_text_scene: PackedScene = preload("res://ui/floating_text.tscn")
@onready var health_component = $HealthComponent

signal is_hurt

func _ready():
	gun.now_bullet_ammo = stats.max_ammo
	GameEvents.player_shot_position.connect(bullet_hit_damage)
	GameEvents.refresh_coin_cost.connect(player_coin_cost)
	GameEvents.player_coins_cost.connect(player_coin_cost)
	GameEvents.game_over.connect(game_over_state)
	GameEvents.crosshair_position.connect(get_crosshair_pos)
	GameEvents.round_start.connect(reset_control_flags)
	if long_hair == true:
		GameEvents.screen_changed.connect(hair_line_changed)
	invincible_frame.timeout.connect(_on_invincible_frame_end)
	# halo 在 _process 里逐帧 lerp，属纯视觉渲染帧驱动；关闭物理插值避免二次插值
	halo.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

func _process(delta: float) -> void:
	_update_invincible_flash(delta)

# 闪烁节点按角色结构选择：长发角色由 CanvasGroup 包住身体（Graphics 在其下），
# 光环与枪是根子节点；其余角色只有 Graphics。与旧 "Invincible frame" 动画轨道一致。
func _resolve_flash_nodes() -> Array[Node]:
	var out: Array[Node] = []
	if has_node("CanvasGroup"):
		for node_name in ["CanvasGroup", "GraphicsHalo", "GraphicsGun"]:
			var node := get_node_or_null(node_name)
			if node != null:
				out.append(node)
	else:
		var graphics_node := get_node_or_null("Graphics")
		if graphics_node != null:
			out.append(graphics_node)
	return out

func _set_flash_visible(value: bool) -> void:
	for node in _flash_nodes:
		if is_instance_valid(node):
			node.visible = value

func _start_invincible_flash() -> void:
	if _flash_nodes.is_empty():
		_flash_nodes = _resolve_flash_nodes()
	if _flash_nodes.is_empty():
		return
	# 旧的固定时长动画不再参与，避免与代码控制的 visible 互相覆盖
	invincible_frame_anim.stop()
	_flashing = true
	_flash_accum = 0.0
	_flash_tick = 0
	_set_flash_visible(true)

func _stop_invincible_flash() -> void:
	if not _flashing:
		return
	_flashing = false
	_set_flash_visible(true)

func _update_invincible_flash(delta: float) -> void:
	if not _flashing:
		return
	# 跳跃/飞行/倒地等状态不走 tick_physics 的收尾，这里按计时器兜底恢复可见
	if invincible_frame.time_left <= 0.0:
		_stop_invincible_flash()
		return
	_flash_accum += delta
	while _flash_accum >= INVINCIBLE_FLASH_INTERVAL:
		_flash_accum -= INVINCIBLE_FLASH_INTERVAL
		_flash_tick += 1
		_set_flash_visible((_flash_tick % 2) == 0)

func reset_control_flags():
	# 回合边界复位控制开关，防止 can_control/can_move/player_stop 被覆盖层或异常路径残留锁死。
	if stats.hp > 0:
		player_stop = false
		can_control = true
		can_move = true
		can_jump = true

func _is_on_floor():
	if sprite_2d.position.y == -17:
		return true

func get_crosshair_pos(crosshair_position: Vector2):
	crosshair_pos = crosshair_position * get_canvas_transform()

func hair_line_changed(n: float):
	$CanvasGroup.material.set_shader_parameter("outline_width", n)

func game_over_state(player_dead: bool):
	if stats.hp <= 0:
		player_stop = true

func get_downed() -> bool:
	return is_downed

# 联机倒地/复起的最小状态接口；具体表现（视觉、救援输入、操作禁用）由 mod 负责。
func set_downed_state(value: bool) -> void:
	if is_downed == value:
		return
	is_downed = value
	if is_downed:
		player_stop = true
		velocity = Vector2.ZERO
		if gun != null and gun.get("is_shoot") != null:
			gun.is_shoot = false
		_apply_downed_visual(true)
		if smoke != null:
			smoke.emitting = false
		add_text(_downed_text("lan_player_down", "DOWN!"))
		GameEvents.player_downed.emit(self)
		ExtensionHooks.notify_named("on_player_downed", [self])
	else:
		player_stop = false
		_apply_downed_visual(false)
		add_text(_downed_text("lan_player_revived", "REVIVED!"))
		GameEvents.player_revived.emit(self)
		ExtensionHooks.notify_named("on_player_revived", [self])


func _apply_downed_visual(is_down: bool) -> void:
	var tint: Color = Color(0.55, 0.6, 0.8, 1.0) if is_down else Color(1, 1, 1, 1)
	if sprite_2d != null:
		sprite_2d.modulate = tint
	if halo != null:
		halo.modulate = tint
	if graphics != null:
		graphics.modulate = tint


func _downed_text(key: String, fallback: String) -> String:
	var text: String = tr(key)
	if text.is_empty() or text == key:
		return fallback
	return text


# 联机可选：角色专属状态（默认汇总子节点 PS；具体角色可覆写整段）
func get_network_character_state() -> int:
	var s: int = 0
	for c in get_children():
		if c.has_method("get_network_character_state"):
			s |= int(c.call("get_network_character_state"))
	return s

func apply_network_character_state(state: int) -> void:
	for c in get_children():
		if c.has_method("apply_network_character_state"):
			c.call("apply_network_character_state", state)

# 联机可选：角色专属逐帧视觉（如跟随 sprite 的持续粒子/偏移）。镜像端每帧调用，
# 只准写视觉节点；默认转发子节点 PS（具体角色可覆写整段）。
func apply_network_character_visual(sprite_y: float, delta: float) -> void:
	for c in get_children():
		if c.has_method("apply_network_character_visual"):
			c.call("apply_network_character_visual", sprite_y, delta)

func get_network_heading_direction() -> Vector2:
	return Vector2.ZERO

func apply_network_heading_direction(_dir: Vector2) -> void:
	pass

# 联机可选：角色专属一次性事件（EX/拍地等）。角色子脚本在事件点调 broadcast_character_event，
# 并实现 apply_network_character_event 供其它端镜像回放（默认转发给子节点）。
func broadcast_character_event(event_name: StringName, event_data: Dictionary = {}) -> void:
	ExtensionHooks.notify_named("on_character_event", [self, event_name, event_data])

func apply_network_character_event(event_name: StringName, event_data: Dictionary) -> void:
	for c in get_children():
		if c.has_method("apply_network_character_event"):
			c.call("apply_network_character_event", event_name, event_data)

func _unhandled_input(event:InputEvent ) -> void:
	
	if player_stop == false:
		if event.is_action_pressed("move_jump") and can_jump == true :
			is_jump_request = true
		
		if event.is_action_pressed("pause") :
			pause_screen.show_pause()
		
		if event.is_action_pressed("fire"):
			gun.is_shoot = true
		
		if event.is_action_released("fire"):
			gun.is_shoot = false
		
		if event.is_action_pressed("kick") and kick != null and allow_kick:
			kick.kick_start()
		
		if event.is_action_pressed("reload"):
			gun._ammo_reload()

func tick_physics(state: State, delta: float) -> void:
	ACCELERATION = stats.MAX_SPEED / stats.SPEED_TIME
	
	if jump_cd_timer.time_left > 0:
		update_jump_cd_bar()
	stats.ammo = ceil(gun.now_bullet_ammo)
	
	
	if can_move == true:
		match state:
			State.IDLE:
				_on_invincible_frame_end()
				move(0.0, delta, ACCELERATION, stats.MAX_SPEED)
				
			State.RUNNING:
				_on_invincible_frame_end()
				move(0.0, delta, ACCELERATION, stats.MAX_SPEED)
				
			State.JUMP:
				move(0.0, delta, ACCELERATION * 1.2, stats.MAX_SPEED * 2)
				
			State.FLY:
				move(gravity / 25, delta, ACCELERATION / 2, stats.MAX_SPEED)
				
			State.FALL:
				move(gravity / 5, delta, ACCELERATION / 2, stats.MAX_SPEED)
	
	if jump_cd_timer.time_left > 0.1:
		is_jump_request = false
	
	if player_stop == false:
		sprite_2d.look_at(crosshair_pos)
		if mortar == false:
			gun.look_at(crosshair_pos)
		else:
			var r := get_angle_to(crosshair_pos)
			if r <= 0 and r > -PI/2:
				gun.rotation = r * 0.2 - PI * 0.4
			elif r <= -PI/2:
				gun.rotation = -r * 0.2 - PI * 0.6
			elif r > 0 and r <= PI/2:
				gun.rotation = -r * 0.2 - PI * 0.4
			elif r > PI/2:
				gun.rotation = r * 0.2 - PI * 0.6
		if kick != null and kick.get("can_r") != false:
			kick.look_at(crosshair_pos)
	gun.position.y = sprite_2d.position.y + gun_root
	halo_root.position.y = sprite_2d.position.y - halo_root_position
	if long_hair == true:
		$GraphicsGun/Hat.position.y = sprite_2d.position.y - hat_position
		$GraphicsGun.scale.x = graphics.scale.x
		$GraphicsHalo.scale.x = graphics.scale.x
	
	
	if sprite_2d.rotation_degrees > 5:
		sprite_2d.rotation_degrees = 5
	elif sprite_2d.rotation_degrees < -10:
		sprite_2d.rotation_degrees = -10
	
	set_player_lookat(crosshair_pos)
	
	if halo.position.distance_to(halo_root.position) > 0:
		halo.position = lerp(halo.position, halo_root.position, 5 * delta)
	
	while is_run_request == true and run_sounds_timer.time_left == 0:
		run_sounds_timer.start()
	
	if is_run_request ==false:
		run_sounds_timer.stop()
	
	if run_sounds_timer.time_left == run_sounds_timer.wait_time:
		run_sounds.pitch_scale = randf_range(0.75 * base_pitch_scale, 1 * base_pitch_scale)
		run_sounds.play()

func move(gravity: float, delta: float, ACCELERATION: float ,MAX_SPEED: float ) -> void:
	
	var movement_vector = get_movement_vector()
	var direction = movement_vector.normalized()
	
	if Game.control_mode != 0:
		direction = movement_vector
	
	if player_stop == true:
		direction = Vector2.ZERO
	velocity.x = move_toward(velocity.x, direction.x * stats.MAX_SPEED, ACCELERATION * delta)
	velocity.y = move_toward(velocity.y, direction.y * stats.MAX_SPEED, ACCELERATION * delta)
	
	if jump_timer.time_left > 0:
		sprite_2d.position.y -= (JUMP_SPEED / (delta + 1.2)) * Engine.time_scale
		
	else:sprite_2d.position.y += gravity * delta * Engine.time_scale
	
	if sprite_2d.position.y > -17:
		sprite_2d.position.y = -17
	
	move_and_slide()
	
	var collision = get_last_slide_collision()
	if collision:
		if velocity.length() > (stats.MAX_SPEED * 2):
			velocity = velocity.bounce(collision.get_normal()) * 0.4

func set_player_lookat(dir):
	if dir != null:
		look_dir = sprite_2d.global_position + (dir * 1000)
		if dir.x > position.x :
			graphics.scale.x = 1
			halo.flip_h = false

		elif dir.x < position.x :
			graphics.scale.x = -1
			halo.flip_h = true

	else:
		look_dir = null

func get_movement_vector():
	if can_control == true:
		var x_movement: float = Input.get_axis("move_left", "move_right")
		var y_movement: float = Input.get_axis("move_up", "move_down")
		
		return Vector2(x_movement, y_movement)
	else:
		return Vector2.ZERO

func get_next_state(state: State) -> State:
	var is_floor := sprite_2d.position.y == -17
	var can_jump :int= is_floor and jump_cd_timer.time_left == 0
	var is_fly :int= fly_timer.time_left > 0
	var is_still := velocity.x == 0 and velocity.y == 0 and is_floor
	var is_fall :int= fly_timer.time_left == 0 and not is_floor
	var is_jump :int= jump_timer.time_left > 0 and can_jump
	
	if is_jump_request == true and can_jump:
		return State.JUMP
	
	match state:
		
		State.IDLE:
			if not is_still:
				return State.RUNNING
			
		
		State.RUNNING:
			if is_still:
				return State.IDLE
			
		
		State.JUMP:
			if jump_timer.time_left == 0:
				return State.FLY
	
		State.FLY:
			if is_fall:
				return State.FALL
				
		State.FALL:
			if is_floor:
				hurt_box.set_dodge(false)
				return State.IDLE
		
		
	return state

func transition_state(from:State, to: State) -> void:
	
	match to:
		State.IDLE:
			z_index = 0
			sprite_2d.play("idle")
			smoke.emitting = false
			is_run_request = false
	
		State.RUNNING:
			sprite_2d.play("run")
			smoke.emitting = true
			is_run_request = true
		
		State.JUMP:
			z_index = 3
			sprite_2d.play("jump")
			jump_timer.start()
			jump_cd_timer.start()
			jump_sounds.play()
			hurt_box.set_dodge(true)
			smoke.emitting = true
			is_run_request = false
			GameEvents.emit_player_jump(self.global_position)
		
		State.FLY:
			sprite_2d.play("jump")
			fly_timer.start()
			smoke.emitting = false
			is_run_request = false
		
		State.FALL:
			sprite_2d.play("jump")
			smoke.emitting = false
			is_run_request = false
			

func _on_invincible_frame(anim: bool):
	
	hurt_box.call_deferred("set_invulnerable", true)
	if anim == true:
		_start_invincible_flash()
		if long_hair == false:
			sprite_2d.material.set_shader_parameter("flash_opacity", 1)
			halo.material.set_shader_parameter("flash_opacity", 0.5)
			await  get_tree().create_timer(0.1).timeout
			sprite_2d.material.set_shader_parameter("flash_opacity", 0.3)
			halo.material.set_shader_parameter("flash_opacity", 0.3)
		else:
			$CanvasGroup.material.set_shader_parameter("flash_opacity", 1)
			halo.material.set_shader_parameter("flash_opacity", 0.5)
			await  get_tree().create_timer(0.1).timeout
			$CanvasGroup.material.set_shader_parameter("flash_opacity", 0.3)
			halo.material.set_shader_parameter("flash_opacity", 0.3)


func _on_invincible_frame_end():
	var is_floor := sprite_2d.position.y == -17
	if invincible_frame.time_left <= 0:
		_stop_invincible_flash()
		if is_floor:
			hurt_box.set_invulnerable(false)
			on_hit = false
		if long_hair == false:
			sprite_2d.material.set_shader_parameter("flash_opacity", 0)
			halo.material.set_shader_parameter("flash_opacity", 0)
		else :
			$CanvasGroup.material.set_shader_parameter("flash_opacity", 0)
			halo.material.set_shader_parameter("flash_opacity", 0)

func apply_knockback(knockback_velocity: Vector2):
	if knockback_velocity != Vector2.ZERO and can_knockback:
		self.velocity = knockback_velocity

func add_text(text: String):
	
	var floating_text = PoolManager.get_pool("floating_text")
	if floating_text == null or floating_text.is_idle == 0:
		floating_text = floating_text_scene.instantiate() as Node2D
		get_tree().get_first_node_in_group("ForegroundLayer").add_child(floating_text)
	
	floating_text.set_style(Color(0.8, 0.8, 0.8), 18)
	floating_text.global_position = global_position + (Vector2.UP * randf_range(15,25)) + (Vector2.RIGHT * randf_range(-15,15))
	floating_text.start(text)

func bullet_hit_damage(_shot_position: Vector2, bullet_body: Node):
	bullet_body.damage_data = DamageData.fill(bullet_body.damage_data, {
		"knockback": stats.bullet_knockback,
		"type": GameTags.BULLET_DAMAGE,
		"source": GameTags.PLAYER,
		"node": bullet_body,
	})
	if bullet_body.has_method("apply_penetrate_dealt"):
		bullet_body.apply_penetrate_dealt()
	var luck = randf_range(0, 100)
	var base_damage: int
	if luck < stats.critical_luck:
		bullet_body.damage_data.is_crit = true
		base_damage = max(1, round(stats.bullet_damage * stats.global_damage * stats.critical_damage))
		GameEvents.emit_player_shot_critical(bullet_body)
	else:
		bullet_body.damage_data.is_crit = false
		base_damage = max(1, round(stats.bullet_damage * stats.global_damage))
		GameEvents.emit_player_shot_not_critical(bullet_body)
	bullet_body.damage_data.base_damage = _apply_player_damage_mult(bullet_body, base_damage)
	
	if !damage_types.is_empty():
		for type in damage_types:
			bullet_body.damage_data.damage_type.append(type)
	
	if !damage_modifier.is_empty():
		for mod in damage_modifier:
			bullet_body.damage_data.damage_modifier.append(mod)
	
	if !damage_dealt.is_empty():
		for dealt in damage_dealt:
			bullet_body.damage_data.on_damage_dealt.append(dealt)
	
	if !flags.is_empty():
		for i in flags:
			bullet_body.damage_data.flags.append(i)
		flags.clear()
	
	bullet_body.scale = Vector2( stats.bullet_scale, stats.bullet_scale )

func refresh_bullet_damage(bullet_body: Node):
	if bullet_body.damage_data == null:
		return
	var luck = randf_range(0, 100)
	var base_damage: int
	if luck < stats.critical_luck:
		bullet_body.damage_data.is_crit = true
		base_damage = max(1, round(stats.bullet_damage * stats.global_damage * stats.critical_damage))
	else:
		bullet_body.damage_data.is_crit = false
		base_damage = max(1, round(stats.bullet_damage * stats.global_damage))
	bullet_body.damage_data.base_damage = _apply_player_damage_mult(bullet_body, base_damage)

func _apply_player_damage_mult(bullet_body: Node, base_damage: int) -> int:
	var damage_mult := float(bullet_body.get_meta("player_damage_mult", 1.0))
	if is_equal_approx(damage_mult, 1.0):
		return base_damage
	return max(1, round(float(base_damage) * damage_mult))

func update_jump_cd_bar():
	jump_cd_bar.visible = true
	jump_cd_bar.value = ( jump_cd_timer.time_left / jump_cd_timer.wait_time ) * 0.87 + 0.05

func is_player_stop():
	if player_stop == false:
		player_stop = true
		self.velocity = Vector2.ZERO
		gun.is_shoot = false
	else:
		player_stop = false

func player_coin_cost(coin_cost: int):
	stats.coin -= coin_cost

func _on_jump_cd_timer_timeout():
	jump_cd_bar.visible = false

func _on_is_hurt():
	pass
	#_on_hurt()

func _on_stats_pick_up_range_changed():
	collision_shape_2d.get_shape().radius = stats.pick_up_range

func _on_pick_box_area_entered(area):
	if area.is_in_group("PickItem") :
		area.target = self
		area.pick_up = true
