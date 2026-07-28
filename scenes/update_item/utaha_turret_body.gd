extends CharacterBody2D


enum State {
	IDLE,
	SHOOT,
}


signal shoot_bullet(bullet_body: Node)

@export var stats: SummonedStats

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
@onready var summoned_buff_manager = $SummonedBuffManager

@onready var bullet = preload("res://scenes/bullet/normal_bullet.tscn")

var move_target: Vector2 = Vector2.ZERO
var shoot_target: Vector2

var spawn_point: Vector2 = Vector2(704, 448)

var enemy_body: Array =[]

var v: float
var player: Node

var hurt_dir: Vector2
var hurt_knockback: int
var summoned_ammo:int = 50

var ACCELERATION: float

var shoot_mod: bool = false

func _ready():
	player = get_tree().get_first_node_in_group("Player")
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
		var rand_r = randf_range(-PI, PI)
		v = rand_r

func round_rand_position():
	var turret_position = spawn_point + Vector2( randf_range(-80,80), randf_range(-50,50)  )
	self.global_position = turret_position
	get_rand_rotation()

func tick_physics(state: State, delta: float) -> void:
	
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
		
		var r: float
		for sprite in turret.get_children():
			sprite.rotation = move_toward(sprite.rotation, v, delta * 10)
			r = sprite.rotation
		shoot_r.rotation = r
	
	if enemy_body.size() > 0:
		shoot_mod = true
	else:
		shoot_mod = false

func shoot_time_count():
	if stats.summoned_shoot_time > 0:
		shoot_timer.wait_time = float(60.0 / stats.summoned_shoot_time )
	if shoot_timer.time_left <= 0:
		_shoot_bullet.call_deferred()
		shoot_timer.start()


func shoot_enemy():
	if !enemy_body.is_empty():
		shoot_target = enemy_body[0].global_position
		v = (shoot_target - self .global_position).angle()



func move(gravity: float, delta: float, ACCELERATION: float ,MAX_SPEED: float ) -> void:
	
	var direction = move_target.normalized()
	
	velocity.x = move_toward(velocity.x, direction.x * stats.summoned_speed, ACCELERATION * delta)
	velocity.y = move_toward(velocity.y, direction.y * stats.summoned_speed, ACCELERATION * delta)
	
	move_and_slide()
	
	var collision = get_last_slide_collision()
	if collision:
		if velocity.length() > (stats.summoned_speed * 2):
			velocity = velocity.bounce(collision.get_normal()) * 0.4

func get_next_state(state: State) -> State:

	
	match state:
		
		State.IDLE:
			if shoot_mod:
				return State.SHOOT
			
		State.SHOOT:
			if not shoot_mod:
				return State.IDLE
		
	return state

func transition_state(from:State, to: State) -> void:
	
	match to:
		State.IDLE:
			pass
	
		State.SHOOT:
			pass

func get_rand_rotation():
	var icon_r = randf_range(-PI, PI)
	utaha_turret_icon.v = icon_r


func bullet_hit_damage(bullet_body: Node):
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		bullet_body.is_critical = true
		bullet_body.bullet_damage = max(1, round((player.stats.bullet_damage * 0.2 + stats.summoned_damage) * player.stats.global_damage *  player.stats.critical_damage * stats.summoned_damage_mult))
		GameEvents.emit_summoned_shot_critical(bullet_body)
	else:
		bullet_body.bullet_damage = max(1, round((player.stats.bullet_damage * 0.2 + stats.summoned_damage) * player.stats.global_damage * stats.summoned_damage_mult))
		GameEvents.emit_summoned_shot_not_critical(bullet_body)
	
	bullet_body.is_summoned_shoot = true
	
	bullet_body.penetrate = player.stats.bullet_penetrate
	bullet_body.collision_num = player.stats.collision_num
	
	bullet_body.bullet_knockback = player.stats.bullet_knockback
	bullet_body.scale = Vector2( player.stats.bullet_scale, player.stats.bullet_scale )
	bullet_body.kill_time = player.stats.bullet_kill_time * 10

func emit_shot_bullet(bullet_body: Node):
	shoot_bullet.emit(bullet_body)

func reload_ammo():
	if reload_timer.time_left <= 0:
		reload_timer.start()
		if !animation_player.is_playing():
			animation_player.play("reload")

func _shoot_bullet():
	if player == null:
		return
	
	if summoned_ammo > 0:
		summoned_ammo -= 1
	else:
		reload_ammo()
		return
	
	if player.stats.bullet_count == 1:
		
		var now_bullet = PoolManager.get_pool("normal_bullet")
		var add_bullet: bool = false
		
		if now_bullet == null or now_bullet.is_idle == 0:
			now_bullet = bullet.instantiate()
			add_bullet = true
		
		now_bullet.speed = stats.summoned_bullet_speed
		now_bullet.position = shoot.global_position
		now_bullet.global_rotation = shoot_r.rotation
		
		
		now_bullet.active_state()
		if add_bullet == true:
			get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
		emit_shot_bullet(now_bullet)
	
	else:
		for i in player.stats.bullet_count:
			
			var now_bullet = PoolManager.get_pool("normal_bullet")
			var add_bullet: bool = false
			
			if now_bullet == null or now_bullet.is_idle == 0:
				now_bullet = bullet.instantiate()
				add_bullet = true
			
			now_bullet.speed = stats.summoned_bullet_speed
			now_bullet.position = shoot.global_position
			
			var arc_rad = deg_to_rad(player.stats.bullet_arc)
			var increment = arc_rad / (player.stats.bullet_count - 1)
			now_bullet.global_rotation = (
				shoot_r.rotation +
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
	now_shoot_flash.rotation = shoot_r.rotation
	now_shoot_flash.active_state()
	
	SoundManager.play_sfx("GunSounds4")
	_shootAnim()

func _shootAnim():
	for sprite_2d in turret.get_children():
		var tween = get_tree().create_tween().set_parallel(true)
		tween.tween_property(sprite_2d, "scale", Vector2(sprite_2d.scale.x,sprite_2d.scale.y), min(shoot_timer.wait_time, 0.3)).from(Vector2(sprite_2d.scale.x - 0.15, sprite_2d.scale.y + 0.4))

func sort_enemy():
	if enemy_body.size() != 0:
		enemy_body.sort_custom(
			func(x, y):
				return x.global_position.distance_to(self.global_position) < y.global_position.distance_to(self.global_position)
		)

func _on_hurt():
	if hurt_knockback != 0:
		self.velocity = hurt_dir * hurt_knockback
		get_rand_rotation()

func _on_reload_timer_timeout():
	summoned_ammo = stats.summoned_max_ammo
	if animation_player.is_playing():
		animation_player.play("RESET")

func _on_area_2d_body_entered(body):
	if body.is_in_group("Enemy"):
		enemy_body.append(body)
	sort_enemy()

func _on_area_2d_body_exited(body):
	if body.is_in_group("Enemy")  and enemy_body.has(body):
		enemy_body.remove_at(enemy_body.find(body))
	sort_enemy()
