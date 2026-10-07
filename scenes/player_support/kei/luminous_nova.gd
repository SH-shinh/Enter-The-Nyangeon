extends Node2D
class_name SummonedGun

signal shoot_bullet(bullet_body: Node)

@export var stats: SummonedStats
@export var pool_id: String
@export var sound_id: String
@export var bullet: PackedScene
@export var shoot_flash: PackedScene = preload("res://scenes/weapon/Unique_Idea/shoot_flash.tscn")
@export var player_damage_mult: float = 0.5

@onready var shoot: Marker2D = $ShootPosition
@onready var reload_timer: Timer = $ReloadTimer
@onready var sprite_2d: Sprite2D = $Sprite2D
@onready var shoot_timer: Timer = $ShootTimer
@onready var fire_sounds: AudioStreamPlayer2D = $FireSounds
@onready var fire_anim = $FireAnim

var player: Node

var summoned_ammo: int

func _ready() -> void:
	player = get_tree().get_first_node_in_group("Player")
	reload_timer.timeout.connect(_on_reload_timer_timeout)
	shoot_bullet.connect(bullet_hit_damage)
	GameEvents.global_time_count.connect(time_count)

func reload_ammo():
	if reload_timer.time_left <= 0:
		reload_timer.start()

func time_count():
	if stats.summoned_shoot_time > 0:
		shoot_timer.wait_time = float(60.0 / stats.summoned_shoot_time )

func _shoot():
	if shoot_timer.time_left <= 0:
		_shoot_bullet()
		shoot_timer.start()

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
			bullet, pool_id, "BulletRoot", self, Faction.PLAYER_SIDE,
			shoot.global_position, self.global_rotation, Vector2.ZERO,
			true, false, true,
			Callable(self, "_configure_bullet"),
			Callable(self, "_pre_activate_bullet")
		)
	else:
		var arc_rad = deg_to_rad(player.stats.bullet_arc)
		var increment = arc_rad / (player.stats.bullet_count - 1)
		for i in player.stats.bullet_count:
			ProjectileSpawner.spawn_core(
				bullet, pool_id, "BulletRoot", self, Faction.PLAYER_SIDE,
				shoot.global_position, self.global_rotation + increment * i - arc_rad / 2, Vector2.ZERO,
				true, false, true,
				Callable(self, "_configure_bullet"),
				Callable(self, "_pre_activate_bullet")
			)

func _configure_bullet(node: Node) -> void:
	node.speed = stats.summoned_bullet_speed

func _pre_activate_bullet(node: Node) -> void:
	emit_shot_bullet(node)
	
	if PoolManager.fx_allowed(&"muzzle_flash"):
		var now_shoot_flash = PoolManager.get_pool("summoned_flash_1")
		if now_shoot_flash == null or now_shoot_flash.is_idle == 0:
			now_shoot_flash = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash)
		now_shoot_flash.position = shoot.global_position
		now_shoot_flash.rotation = self.global_rotation
		now_shoot_flash.active_state()
	
	if sound_id != "":
		SoundManager.play_sfx(sound_id)
	else:
		fire_sounds.play()
	_shootAnim()

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
		bullet_body.damage_data.base_damage = max(1, round((player.stats.bullet_damage * player_damage_mult + stats.summoned_damage) * player.stats.global_damage *  player.stats.critical_damage * stats.summoned_damage_mult))
		GameEvents.emit_summoned_shot_critical(bullet_body)
	else:
		bullet_body.damage_data.is_crit = false
		bullet_body.damage_data.base_damage = max(1, round((player.stats.bullet_damage * player_damage_mult + stats.summoned_damage) * player.stats.global_damage * stats.summoned_damage_mult))
		GameEvents.emit_summoned_shot_not_critical(bullet_body)
	
	bullet_body.penetrate = player.stats.bullet_penetrate
	bullet_body.collision_num = player.stats.collision_num
	
	bullet_body.scale = Vector2( player.stats.bullet_scale, player.stats.bullet_scale )
	bullet_body.kill_time = player.stats.bullet_kill_time * 10

func _shootAnim(dur: float = -1.0):
	# 远端回放时用 action 携带的射速时长覆盖本机 ShootTimer，避免镜像后坐速度与拥有者不一致
	var wait: float = shoot_timer.wait_time
	if dur > 0.0:
		wait = dur
	var anim_speed: float = max(1, 0.3 / max(0.001, wait))
	fire_anim.play("RESET")
	fire_anim.play("fire", -1, anim_speed, false)

func emit_shot_bullet(bullet_body: Node):
	shoot_bullet.emit(bullet_body)

func _on_reload_timer_timeout():
	summoned_ammo = stats.summoned_max_ammo
