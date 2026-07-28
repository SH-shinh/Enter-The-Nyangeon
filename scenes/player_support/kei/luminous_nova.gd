extends Node2D

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
		
		var now_bullet = PoolManager.get_pool(pool_id)
		var add_bullet: bool = false
		
		if now_bullet == null or now_bullet.is_idle == 0:
			now_bullet = bullet.instantiate()
			add_bullet = true
		
		now_bullet.speed = stats.summoned_bullet_speed
		now_bullet.position = shoot.global_position
		now_bullet.global_rotation = self.global_rotation
		
		
		now_bullet.active_state()
		if add_bullet == true:
			get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
		emit_shot_bullet(now_bullet)
	
	else:
		for i in player.stats.bullet_count:
			
			var now_bullet = PoolManager.get_pool(pool_id)
			var add_bullet: bool = false
			
			if now_bullet == null or now_bullet.is_idle == 0:
				now_bullet = bullet.instantiate()
				add_bullet = true
			
			now_bullet.speed = stats.summoned_bullet_speed
			now_bullet.position = shoot.global_position
			
			var arc_rad = deg_to_rad(player.stats.bullet_arc)
			var increment = arc_rad / (player.stats.bullet_count - 1)
			now_bullet.global_rotation = (
				self.global_rotation +
				increment * i -
				arc_rad / 2
			)
			
			now_bullet.active_state()
			if add_bullet == true:
				get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
			emit_shot_bullet(now_bullet)
	
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
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		bullet_body.is_critical = true
		bullet_body.bullet_damage = max(1, round((player.stats.bullet_damage * player_damage_mult + stats.summoned_damage) * player.stats.global_damage *  player.stats.critical_damage * stats.summoned_damage_mult))
		GameEvents.emit_summoned_shot_critical(bullet_body)
	else:
		bullet_body.bullet_damage = max(1, round((player.stats.bullet_damage * player_damage_mult + stats.summoned_damage) * player.stats.global_damage * stats.summoned_damage_mult))
		GameEvents.emit_summoned_shot_not_critical(bullet_body)
	
	bullet_body.is_summoned_shoot = true
	
	bullet_body.penetrate = player.stats.bullet_penetrate
	bullet_body.collision_num = player.stats.collision_num
	
	bullet_body.bullet_knockback = player.stats.bullet_knockback
	bullet_body.scale = Vector2( player.stats.bullet_scale, player.stats.bullet_scale )
	bullet_body.kill_time = player.stats.bullet_kill_time * 10

func _shootAnim():
	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property($Sprite2D, "scale", Vector2(sprite_2d.scale.x,sprite_2d.scale.y), min(shoot_timer.wait_time, 0.3)).from(Vector2(sprite_2d.scale.x - 0.15, sprite_2d.scale.y + 0.4))

func emit_shot_bullet(bullet_body: Node):
	shoot_bullet.emit(bullet_body)

func _on_reload_timer_timeout():
	summoned_ammo = stats.summoned_max_ammo
