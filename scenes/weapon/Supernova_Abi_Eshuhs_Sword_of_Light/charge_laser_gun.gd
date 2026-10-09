extends PlayerGun


@export var laser_beam: PackedScene
@export var charge_time: float = 1.0
@export var laser_drain_rate: float = 30.0
@export var charge_speed_mult: float = 0.5
@export var laser_shake_range: float = 3.5
@export var laser_shake_freq: float = 0.05
@export var follow_speed: float = 8.0
@export var fire_anim_speed: float = 1.0
@export var min_charge_energy_ratio: float = 0.3
@export var hold_delay: float = 0.1
@export var damage_refresh_interval: float = 1.0


var is_holding: bool = false
var is_charged: bool = false
var charge_timer: float = 0.0
var hold_timer: float = 0.0
var laser: Node = null
var laser_tick_mult: float = -1.0
var _damage_refresh_timer: float = 0.0
var _shake_timer: float = 0.0
var aim_angle: float = 0.0
var _muzzle_flash_timer: float = 0.0

@onready var charge_particles: GPUParticles2D = $ChargeParticles
@onready var charge_ring_particles: GPUParticles2D = $ChargeRingParticles
@onready var charge_sound: AudioStreamPlayer2D = $ChargeSounds


func _physics_process(delta: float) -> void:
	if now_bullet_ammo > stats.max_ammo:
		now_bullet_ammo = stats.max_ammo
	if stats.bullet_shoot_time > 0:
		shoot_timer.wait_time = float(60.0 / stats.bullet_shoot_time)

	if player == null:
		return

	_update_aim(delta)

	if is_shoot:
		if not is_holding:
			is_holding = true
			hold_timer = 0.0
			charge_timer = 0.0
			is_charged = false
			return

		hold_timer += delta

		var can_charge: bool = hold_timer >= hold_delay and player.energy >= player.max_energy * min_charge_energy_ratio

		if not is_charged and can_charge and not in_ammo_reload:
			can_reload_ammo = false
			charge_timer += delta
			if charge_timer >= charge_time:
				is_charged = true

		var is_charging: bool = not is_charged and can_charge and not in_ammo_reload
		_set_charge_mode(is_charged or is_charging)
		if is_charging:
			_charge_particles(true)
			_charge_sound_loop()
		else:
			_charge_particles(false)
			_charge_sound_stop()

		if is_charged and player.energy > 0.0:
			_set_laser(true)
			_update_laser(delta)
			_refresh_laser_damage(delta)
			player.energy = player.energy - laser_drain_rate * stats.bullet_cost * delta
			if player.energy <= 0.0:
				is_charged = false
				charge_timer = 0.0
				_set_laser(false)
			else:
				_laser_shake(delta)
				_play_fire_anim()
				_spawn_muzzle_flash(delta)
				SoundManager.play_loop_sfx("LaserSounds3")
		else:
			_set_laser(false)
	else:
		if is_holding:
			if not is_charged and shoot_timer.time_left <= 0:
				_shoot()
			is_holding = false
			is_charged = false
			charge_timer = 0.0
			_set_charge_mode(false)
			_charge_particles(false)
			_charge_sound_stop()
			_set_laser(false)


func _update_aim(delta: float) -> void:
	var raw := global_position.direction_to(crosshair_pos).angle()
	if is_charged:
		var weight := 1.0 - exp(-follow_speed * delta)
		aim_angle = lerp_angle(aim_angle, raw, weight)
	else:
		aim_angle = raw


func _set_charge_mode(active: bool) -> void:
	if player != null and player.has_method("set_charge_mode"):
		player.set_charge_mode(active)


func _set_laser(active: bool) -> void:
	_set_laser_firing(active)
	if active:
		if not is_instance_valid(laser):
			laser = laser_beam.instantiate()
			get_tree().get_first_node_in_group("BulletRoot").add_child(laser)
		if laser.is_idle == 1:
			
			GameEvents.emit_player_shot_position($ShootPosition.global_position, laser)
			laser.active_state()
			ProjectileSpawner.notify_local(laser, player, Faction.PLAYER_SIDE)
			_apply_laser_tick_mult()
			_damage_refresh_timer = damage_refresh_interval
			SoundManager.play_sfx("LaserSounds2")
	else:
		if is_instance_valid(laser) and laser.is_idle == 0:
			laser.idle_state()
			_stop_fire_anim()
		can_reload_ammo = true
		SoundManager.stop_sfx("LaserSounds3")


func _apply_laser_tick_mult() -> void:
	if not is_instance_valid(laser) or laser.damage_data == null:
		return
	var tick_mult: float = laser_tick_mult if laser_tick_mult >= 0.0 else laser.tick_damage_mult
	laser.damage_data.base_damage *= tick_mult


func _refresh_laser_damage(delta: float) -> void:
	if not is_instance_valid(laser) or laser.damage_data == null:
		return
	_damage_refresh_timer -= delta
	if _damage_refresh_timer > 0.0:
		return
	_damage_refresh_timer = damage_refresh_interval
	if player != null and player.has_method("refresh_bullet_damage"):
		player.refresh_bullet_damage(laser)
	_apply_laser_tick_mult()


func _update_laser(delta: float) -> void:
	if not is_instance_valid(laser):
		return
	laser.follow($ShootPosition.global_position, aim_angle, delta)


func _laser_shake(delta: float) -> void:
	_shake_timer += delta
	if _shake_timer >= laser_shake_freq:
		_shake_timer = 0.0
		GameEvents.emit_shake_screen(stats.shake_length, laser_shake_range * stats.shake_mult, laser_shake_freq)


func _play_fire_anim() -> void:
	fire_anim.speed_scale = fire_anim_speed
	if not fire_anim.is_playing():
		fire_anim.play("fire")
		var recoil_direction : Vector2 = Vector2.RIGHT.rotated(self.global_rotation)
		var recoil_speed: Vector2 = recoil_direction * (stats.bullet_recoil + 60)
		player.velocity -= recoil_speed


func _stop_fire_anim() -> void:
	fire_anim.play("RESET")


func _spawn_muzzle_flash(delta: float) -> void:
	_muzzle_flash_timer -= delta
	if _muzzle_flash_timer > 0.0:
		return
	_muzzle_flash_timer = 0.08
	if PoolManager.fx_allowed(&"muzzle_flash"):
		var now_shoot_flash = PoolManager.get_pool("player_flash")
		if now_shoot_flash == null or now_shoot_flash.is_idle == 0:
			now_shoot_flash = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash)
		now_shoot_flash.position = shoot_position.global_position
		now_shoot_flash.rotation = aim_angle
		now_shoot_flash.active_state()


func _charge_particles(active: bool) -> void:
	charge_particles.emitting = active
	charge_ring_particles.emitting = active


func _charge_sound_loop() -> void:
	if not charge_sound.playing:
		charge_sound.play()


func _charge_sound_stop() -> void:
	charge_sound.stop()


func _set_laser_firing(active: bool) -> void:
	if player != null and player.has_method("set_laser_firing"):
		player.set_laser_firing(active)
