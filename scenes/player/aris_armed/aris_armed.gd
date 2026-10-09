extends Player


signal energy_changed(current: float, max_value: float)
signal energy_empty
signal energy_spent(amount: float)


@export var max_energy: float = 100.0
@export var energy_drain_rate: float = 30.0
@export var drain_exp_growth: float = 0.3 # 每秒增长系数 k，每秒消耗 = energy_drain_rate * exp(k * flight_time)
@export var energy_regen_rate: float = 25.0
@export var fly_speed_mult: float = 1.5
@onready var jet_particles_r = $GraphicsHalo/JetParticlesR
@onready var jet_particles_l = $GraphicsHalo/JetParticlesL


var energy_regen_mult: float = 1.0


var energy: float = 100.0:
	set(v):
		var clamped := clampf(v, 0.0, max_energy)
		if energy == clamped:
			return
		if clamped < energy:
			energy_spent.emit(energy - clamped)
		energy = clamped
		energy_changed.emit(energy, max_energy)
		if energy <= 0.0:
			energy_empty.emit()


var is_hovering: bool = false
var flight_time: float = 0.0
var descend_request: bool = false
var charge_speed_mult: float = 1.0
var is_laser_firing: bool = false


@onready var idle_sounds: AudioStreamPlayer2D = $IdleSounds


func _ready() -> void:
	super._ready()
	energy = max_energy


func _unhandled_input(event: InputEvent) -> void:
	if player_stop == false:
		if event.is_action_pressed("move_jump") and can_jump == true:
			_on_jump_toggle_pressed()
		if event.is_action_pressed("pause"):
			pause_screen.show_pause()
		if event.is_action_pressed("fire"):
			gun.is_shoot = true
		if event.is_action_released("fire"):
			gun.is_shoot = false
		if event.is_action_pressed("kick") and kick != null:
			kick.kick_start()
		if event.is_action_pressed("reload"):
			gun._ammo_reload()


func _on_jump_toggle_pressed() -> void:
	if is_hovering:
		descend_request = true
	elif sprite_2d.position.y == -17 and energy > 0.0:
		is_jump_request = true


func tick_physics(state: State, delta: float) -> void:
	super.tick_physics(state, delta)
	if gun != null and gun.has_method("_update_aim"):
		gun.global_rotation = gun.aim_angle
	jet_particles_r.position.y = sprite_2d.position.y + 5
	jet_particles_l.position.y = sprite_2d.position.y + 5
	_update_energy(delta)
	_update_flight_audio()


func get_next_state(state: State) -> State:
	var is_floor := sprite_2d.position.y == -17
	var is_still := velocity.x == 0 and velocity.y == 0 and is_floor

	if is_jump_request == true and is_floor and jump_cd_timer.time_left == 0 and energy > 0.0:
		is_jump_request = false
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
			if descend_request == true or energy <= 0.0:
				descend_request = false
				return State.FALL
		State.FALL:
			if is_floor:
				hurt_box.set_dodge(false)
				return State.IDLE

	return state


func transition_state(from: State, to: State) -> void:
	match to:
		State.IDLE:
			z_index = 0
			sprite_2d.play("idle")
			smoke.emitting = false
			is_run_request = false
		State.RUNNING:
			sprite_2d.play("run")
			smoke.emitting = false
			is_run_request = false
		State.JUMP:
			z_index = 3
			sprite_2d.play("jump")
			jump_timer.start()
			jump_cd_timer.start()
			jump_sounds.play()
			hurt_box.set_dodge(true)
			smoke.emitting = false
			is_run_request = false
			is_hovering = false
			GameEvents.emit_player_jump(global_position)
		State.FLY:
			sprite_2d.play("jump")
			smoke.emitting = false
			is_run_request = false
			is_hovering = true
		State.FALL:
			sprite_2d.play("jump")
			smoke.emitting = false
			is_run_request = false
			is_hovering = false
			jump_sounds.play()


func move(gravity: float, delta: float, ACCELERATION: float, MAX_SPEED: float) -> void:
	var movement_vector: Vector2 = get_movement_vector()
	var direction: Vector2 = movement_vector.normalized()

	if Game.control_mode != 0:
		direction = movement_vector

	if player_stop == true:
		direction = Vector2.ZERO

	var speed: float = stats.MAX_SPEED * charge_speed_mult
	var accel: float = ACCELERATION
	if is_hovering:
		speed = stats.MAX_SPEED * fly_speed_mult * charge_speed_mult
		accel = stats.MAX_SPEED / stats.SPEED_TIME

	velocity.x = move_toward(velocity.x, direction.x * speed, accel * delta)
	velocity.y = move_toward(velocity.y, direction.y * speed, accel * delta)

	if jump_timer.time_left > 0:
		sprite_2d.position.y -= (JUMP_SPEED / (delta + 1.2)) * Engine.time_scale
	elif not is_hovering:
		sprite_2d.position.y += gravity * delta * Engine.time_scale

	if sprite_2d.position.y > -17:
		sprite_2d.position.y = -17

	move_and_slide()

	var collision := get_last_slide_collision()
	if collision:
		if velocity.length() > (stats.MAX_SPEED * 2):
			velocity = velocity.bounce(collision.get_normal()) * 0.4


func _update_energy(delta: float) -> void:
	if is_hovering:
		flight_time += delta
		energy = energy - energy_drain_rate * exp(drain_exp_growth * flight_time) * delta
	else:
		if sprite_2d.position.y == -17:
			flight_time = 0.0
			if not is_laser_firing:
				energy = energy + energy_regen_rate * energy_regen_mult * delta


func _update_flight_audio() -> void:
	var moving := velocity.length_squared() > 1.0
	if moving:
		if not run_sounds.playing:
			idle_sounds.stop()
			run_sounds.play()
	else:
		if not idle_sounds.playing:
			run_sounds.stop()
			idle_sounds.play()


func add_energy(amount: float) -> void:
	energy = energy + amount


func spend_energy(amount: float) -> bool:
	if energy >= amount:
		energy = energy - amount
		return true
	return false


func set_regen_mult(mult: float) -> void:
	energy_regen_mult = mult


func set_charge_mode(active: bool) -> void:
	charge_speed_mult = 0.5 if active else 1.0


func set_laser_firing(active: bool) -> void:
	is_laser_firing = active


# 联机：同步悬浮（喷气）表现
func get_network_character_state() -> int:
	return 1 if is_hovering else 0


func apply_network_character_state(state: int) -> void:
	var hovering: bool = state == 1
	if jet_particles_r != null:
		jet_particles_r.emitting = hovering
	if jet_particles_l != null:
		jet_particles_l.emitting = hovering


# 联机：逐帧随镜像 sprite 同步喷气粒子位置（state 只在变化时回调，承载不了连续位移）
func apply_network_character_visual(_sprite_y: float, _delta: float) -> void:
	var y: float = sprite_2d.position.y + 5.0
	if jet_particles_r != null:
		jet_particles_r.position.y = y
	if jet_particles_l != null:
		jet_particles_l.position.y = y
