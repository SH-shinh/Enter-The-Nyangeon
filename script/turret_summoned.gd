class_name TurretSummoned
extends Summoned

signal shoot_bullet(bullet_body: Node)

enum State {
	IDLE,
	SHOOT,
}

@export var rotate_sprites: bool = false
@export var shoot_flash: PackedScene = preload("res://scenes/weapon/Unique_Idea/shoot_flash.tscn")

@onready var shoot = %Shoot
@onready var turret = %Sprite2D
@onready var shoot_r = $ShootR
@onready var reload_timer = $ReloadTimer
@onready var utaha_turret_icon = %utaha_turret_icon
@onready var shoot_timer = $ShootTimer
@onready var idle_timer = $IdleTimer
@onready var animation_player = $CanvasGroup/Reload/AnimationPlayer
@onready var buff_box = %BuffBox

const bullet = preload("res://scenes/bullet/normal_bullet.tscn")

var move_target: Vector2 = Vector2.ZERO
var shoot_target: Vector2
var v: float
var summoned_ammo: int = 50
var shoot_mod: bool = false

var _recoil_tween: Tween
var _recoil_base: Dictionary = {}

func _ready():
	super._ready()
	GameEvents.screen_changed.connect(outline_changed)
	GameEvents.round_start.connect(round_rand_position)
	shoot_bullet.connect(bullet_hit_damage)
	get_rand_rotation()
	summoned_ammo = stats.summoned_max_ammo
	stats.is_hurt.connect(_on_hurt)

func outline_changed(n: float):
	$CanvasGroup.material.set_shader_parameter("outline_width", n)

func rand_turret():
	if idle_timer.time_left <= 0:
		idle_timer.start()
		v = randf_range(-PI, PI)

func round_rand_position():
	var turret_position = spawn_point + Vector2(randf_range(-80, 80), randf_range(-50, 50))
	global_position = turret_position
	get_rand_rotation()

func tick_physics(state: int, delta: float):
	_prune_enemy_body()
	ACCELERATION = stats.summoned_speed / stats.SPEED_TIME
	match state:
		State.IDLE:
			rand_turret()
			move(0.0, delta, ACCELERATION, stats.summoned_speed)
		State.SHOOT:
			shoot_enemy()
			shoot_time_count()
			move(0.0, delta, ACCELERATION, stats.summoned_speed)
	if rotate_sprites:
		_rotate_turret_visual(delta)
	if enemy_body.size() > 0:
		shoot_mod = true
	else:
		shoot_mod = false

# 把 %Sprite2D 子 sprite 与 shoot_r 转向 v（本体 tick 与远端 apply 共用）
func _rotate_turret_visual(delta: float) -> void:
	var r: float
	for sprite in turret.get_children():
		sprite.rotation = move_toward(sprite.rotation, v, delta * 10)
		r = sprite.rotation
	shoot_r.rotation = r

# 联机：上报/应用视觉转向（proxy 通过这两个方法同步 v）
func get_network_visual_rotation() -> float:
	return v

func apply_network_visual_rotation(rot: float, delta: float) -> void:
	v = rot
	if rotate_sprites:
		_rotate_turret_visual(delta)

# 联机：远端镜像播放动作表现（如开火后坐）
func network_play_action(action: String, dur: float = -1.0) -> void:
	if action == "shoot":
		_shootAnim(dur)
	elif action == "reload":
		if not animation_player.is_playing():
			animation_player.play("reload")

func shoot_time_count():
	if stats.summoned_shoot_time > 0:
		shoot_timer.wait_time = float(60.0 / stats.summoned_shoot_time)
	if shoot_timer.time_left <= 0:
		_shoot_bullet.call_deferred()
		shoot_timer.start()

func shoot_enemy():
	if not enemy_body.is_empty():
		shoot_target = enemy_body[0].global_position
		v = (shoot_target - global_position).angle()

func move(gravity: float, delta: float, accel: float, max_speed: float):
	var dir = move_target.normalized()
	velocity.x = move_toward(velocity.x, dir.x * max_speed, accel * delta)
	velocity.y = move_toward(velocity.y, dir.y * max_speed, accel * delta)
	move_and_slide()
	var collision = get_last_slide_collision()
	if collision and velocity.length() > (max_speed * 2):
		velocity = velocity.bounce(collision.get_normal()) * 0.4

func get_next_state(state: int) -> int:
	match state:
		State.IDLE:
			if shoot_mod:
				return State.SHOOT
		State.SHOOT:
			if not shoot_mod:
				return State.IDLE
	return state

func transition_state(from: int, to: int):
	pass

func get_rand_rotation():
	var icon_r = randf_range(-PI, PI)
	utaha_turret_icon.v = icon_r

func bullet_hit_damage(bullet_body: Node):
	bullet_body.damage_data = DamageData.fill(bullet_body.damage_data, {
		"knockback": player.stats.bullet_knockback,
		"type": GameTags.BULLET_DAMAGE,
		"source": GameTags.SUMMONED,
		"node": bullet_body,
	})
	bullet_body.apply_penetrate_dealt()
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		bullet_body.damage_data.is_crit = true
		bullet_body.damage_data.base_damage = max(1, round((player.stats.bullet_damage * 0.2 + stats.summoned_damage) * player.stats.global_damage * player.stats.critical_damage * stats.summoned_damage_mult))
		GameEvents.emit_summoned_shot_critical(bullet_body)
	else:
		bullet_body.damage_data.is_crit = false
		bullet_body.damage_data.base_damage = max(1, round((player.stats.bullet_damage * 0.2 + stats.summoned_damage) * player.stats.global_damage * stats.summoned_damage_mult))
		GameEvents.emit_summoned_shot_not_critical(bullet_body)
	bullet_body.penetrate = player.stats.bullet_penetrate
	bullet_body.collision_num = player.stats.collision_num
	bullet_body.scale = Vector2(player.stats.bullet_scale, player.stats.bullet_scale)
	bullet_body.kill_time = player.stats.bullet_kill_time * 10

func emit_shot_bullet(bullet_body: Node):
	shoot_bullet.emit(bullet_body)

func reload_ammo():
	if reload_timer.time_left <= 0:
		reload_timer.start()
		if not animation_player.is_playing():
			animation_player.play("reload")
		ExtensionHooks.notify(ExtensionHooks.on_summoned_action, [self, "reload", "", "", Vector2.ZERO, 0.0, 0.0])

func _shoot_bullet():
	if player == null:
		return
	if summoned_ammo > 0:
		summoned_ammo -= 1
	else:
		reload_ammo()
		return
	if player.stats.bullet_count == 1:
		ProjectileSpawner.spawn_core(
			bullet, "normal_bullet", "BulletRoot", self, Faction.PLAYER_SIDE,
			shoot.global_position, shoot_r.rotation, Vector2.ZERO,
			false, false, true,
			Callable(self, "_configure_bullet"),
			Callable(),
			Callable(self, "_post_bullet")
		)
	else:
		var arc_rad = deg_to_rad(player.stats.bullet_arc)
		var increment = arc_rad / (player.stats.bullet_count - 1)
		for i in player.stats.bullet_count:
			ProjectileSpawner.spawn_core(
				bullet, "normal_bullet", "BulletRoot", self, Faction.PLAYER_SIDE,
				shoot.global_position, shoot_r.rotation + increment * i - arc_rad / 2, Vector2.ZERO,
				false, false, true,
				Callable(self, "_configure_bullet"),
				Callable(),
				Callable(self, "_post_bullet")
			)
	var show_flash: bool = PoolManager.fx_allowed(&"muzzle_flash")
	if show_flash:
		var now_shoot_flash = PoolManager.get_pool("summoned_flash_1")
		if now_shoot_flash == null or now_shoot_flash.is_idle == 0:
			now_shoot_flash = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash)
		now_shoot_flash.position = shoot.global_position
		now_shoot_flash.rotation = shoot_r.rotation
		now_shoot_flash.active_state()
		# 标记：该闪光由 on_summoned_action 统一广播，避免 mod 的 SELayer 通用广播重复
		now_shoot_flash.set_meta("coop_action_flash", true)
	SoundManager.play_sfx("GunSounds4")
	_shootAnim()
	ExtensionHooks.notify(ExtensionHooks.on_summoned_action, [
		self, "shoot", "GunSounds4",
		(str(shoot_flash.resource_path) if show_flash else ""),
		shoot.global_position, shoot_r.rotation, _recoil_duration()
	])

func _configure_bullet(node: Node) -> void:
	node.speed = stats.summoned_bullet_speed

func _post_bullet(node: Node) -> void:
	emit_shot_bullet(node)

# 后坐动画时长（拥有者按实际射速；远端由 action 携带的 dur 覆盖）
func _recoil_duration() -> float:
	var dur: float = min(shoot_timer.wait_time, 0.3)
	if dur <= 0.0:
		dur = 0.2
	return dur

# 开火后坐：锚定每个 sprite 的基准 scale（首次记录），并终止上一段 tween。
# 若以"当前 scale"为目标，远端连续开火时前一段未结束会把基准逐步抬高 → scale 不断放大。
func _shootAnim(dur: float = -1.0):
	if turret.get_child_count() == 0:
		return
	if dur <= 0.0:
		dur = _recoil_duration()
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	_recoil_tween = get_tree().create_tween().set_parallel(true)
	for sprite_2d in turret.get_children():
		var base: Vector2
		if _recoil_base.has(sprite_2d):
			base = _recoil_base[sprite_2d]
		else:
			base = sprite_2d.scale
			_recoil_base[sprite_2d] = base
		_recoil_tween.tween_property(sprite_2d, "scale", base, dur).from(Vector2(base.x - 0.15, base.y + 0.4))

func _on_hurt():
	if hurt_knockback != 0:
		velocity = hurt_dir * hurt_knockback
		get_rand_rotation()

func apply_knockback(v: Vector2):
	if v != Vector2.ZERO:
		velocity = v
		get_rand_rotation()

func _on_reload_timer_timeout():
	summoned_ammo = stats.summoned_max_ammo
	if animation_player.is_playing():
		animation_player.play("RESET")
