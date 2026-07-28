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

@onready var fire_sounds = $FireSounds
@onready var reload_sounds = $ReloadSounds
@onready var reload_anim = $ReloadAnim
@onready var sprite_2d = $Sprite2D
@onready var shoot_position = $ShootPosition
@onready var shoot_timer = $ShootTimer
@onready var ammo_reload_timer = $AmmoReloadTimer

var player: Node
var now_bullet_ammo: float
var in_ammo_reload:bool = false
var can_shoot:bool = true
var is_shoot:bool = false

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

func _physics_process(delta):
	if now_bullet_ammo > stats.max_ammo:
		now_bullet_ammo = stats.max_ammo
	if stats.bullet_shoot_time > 0:
		shoot_timer.wait_time = float(60.0 / stats.bullet_shoot_time )
	if player != null and is_shoot == true and shoot_timer.time_left <= 0 and ammo_reload_timer.time_left <= 0 and can_shoot == true :
		_shoot()
		if semi_auto == true:
			is_shoot = false

func  _ammo_reload():
	
	if can_reload_ammo == false:
		return
	
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
	
		else:
			if is_clip == true and now_bullet_ammo <= 0:
				in_ammo_reload = true
				shoot_timer.stop()
				GameEvents.emit_player_ammo_reload(now_bullet_ammo, stats.max_ammo, stats.reload_timer)
				ammo_reload_timer.start()
				reload_sounds.play()
				reload_anim.speed_scale = 1/ammo_reload_timer.wait_time
				reload_anim.play("reload")
			else:
				in_ammo_reload = true
				shoot_timer.stop()
				ammo_reload_timer.start()
				reload_anim.speed_scale = 1/ammo_reload_timer.wait_time
				reload_anim.play("reload_2_start")
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
	_shoot_bullet()
	fire_sounds.play()
	now_bullet_ammo -= stats.bullet_cost
	GameEvents.emit_player_gun_shoot(self)

func _shoot_bullet():
	if stats.bullet_count == 1:
		
		var now_shoot_flash = PoolManager.get_pool("player_flash")
		if now_shoot_flash == null or now_shoot_flash.is_idle == 0:
			now_shoot_flash = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash)
		
		var now_bullet = PoolManager.get_pool(bullet_pool_id)
		var add_bullet: bool = false
		if now_bullet == null or now_bullet.is_idle == 0:
			now_bullet = bullet.instantiate()
			add_bullet = true
		
		var direction: Vector2 = global_position \
				.direction_to(crosshair_pos) \
				.normalized()
		if random_bullet == true:
			now_bullet.speed = stats.bullet_speed * randf_range(0.7,1)
		else:
			now_bullet.speed = stats.bullet_speed
		now_bullet.penetrate = stats.bullet_penetrate
		now_bullet.collision_num = stats.collision_num
		now_bullet.position = shoot_position.global_position
		now_bullet.kill_time = stats.bullet_kill_time * 10
		now_bullet.is_player_shoot = true
		now_bullet.global_rotation = direction.angle()
		shoot_position.rotation = direction.angle()
		if random_sounds == true:
			fire_sounds.pitch_scale = randf_range(0.8, 1.2)
		
		var player = get_tree().get_first_node_in_group("Player")
		var recoil_direction : Vector2 = global_position \
				.direction_to(crosshair_pos) \
				.normalized()
		var recoil_speed = recoil_direction * stats.bullet_recoil
		
		player.velocity -= recoil_speed
		
		
		now_shoot_flash.position = shoot_position.global_position
		now_shoot_flash.rotation = global_rotation
		
		if parabola == true:
			var length = shoot_position.global_position.distance_to(crosshair_pos)
			now_bullet.mouse_length = length
		
		call_deferred("_shootAnim")
		
		if add_bullet == true:
			get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
		GameEvents.emit_player_shot_position(shoot_position.global_position,now_bullet)
		now_shoot_flash.active_state()
		now_bullet.active_state()
	
	else:
		var direction: Vector2 = global_position \
			.direction_to(crosshair_pos) \
			.normalized()
		
		var now_shoot_flash = PoolManager.get_pool("player_flash")
		if now_shoot_flash == null or now_shoot_flash.is_idle == 0:
			now_shoot_flash = shoot_flash.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash)
		now_shoot_flash.position = shoot_position.global_position
		now_shoot_flash.rotation = global_rotation
		now_shoot_flash.active_state()
		
		for i in stats.bullet_count:
			
			var now_bullet = PoolManager.get_pool(bullet_pool_id)
			var add_bullet: bool = false
			if now_bullet == null or now_bullet.is_idle == 0:
				now_bullet = bullet.instantiate()
				add_bullet = true
			if random_bullet == true:
				now_bullet.speed = stats.bullet_speed * randf_range(0.7,1)
			else:
				now_bullet.speed = stats.bullet_speed
			now_bullet.penetrate = stats.bullet_penetrate
			now_bullet.collision_num = stats.collision_num
			now_bullet.position = shoot_position.global_position
			now_bullet.kill_time = stats.bullet_kill_time * 10
			now_bullet.is_player_shoot = true
			
			var arc_rad = deg_to_rad(stats.bullet_arc)
			if random_bullet == true:
				arc_rad *= randf_range(0.8,1.2)
			var increment = arc_rad / (stats.bullet_count - 1)
			now_bullet.global_rotation = (
				direction.angle() +
				increment * i -
				arc_rad / 2
			)
			
			
			var player = get_tree().get_first_node_in_group("Player")
			var recoil_direction : Vector2 = global_position \
					.direction_to(crosshair_pos) \
					.normalized()
			var recoil_speed = recoil_direction * ( stats.bullet_recoil / stats.bullet_count )
		
			player.velocity -= recoil_speed
			
			if parabola == true:
				var length = shoot_position.global_position.distance_to(crosshair_pos)
				now_bullet.mouse_length = length
			
			call_deferred("_shootAnim")
			
			if add_bullet == true:
				get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
			
			GameEvents.emit_player_shot_position(shoot_position.global_position,now_bullet)
			
			now_bullet.active_state()
			
		if random_sounds == true:
			fire_sounds.pitch_scale = randf_range(0.8, 1.2)

func _shootAnim():
	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property($Sprite2D, "scale", Vector2(sprite_2d.scale.x,sprite_2d.scale.y), min(shoot_timer.wait_time, 0.3)).from(Vector2(sprite_2d.scale.x - 0.15, sprite_2d.scale.y + 0.4))
