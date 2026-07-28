extends CharacterBody2D

signal is_hurt
signal is_dead
signal is_knockback
signal turning_mod

enum State {
	IDLE,
	SHOOTING,
	AIMING,
	RUNNING,
	TURNING,
	DEAD,
}

var coin:PackedScene = preload("res://scenes/item/coin.tscn")
@export var pool_id: String
@export var icon:String
@export var stats: EnemyStats
@export var shoot_range: int
@export var back_range: int
@export var aim_and_move: float
@export var shoot_and_move: float
@export_range(0,100) var surround_tendency: int
@export var surround_time: int
@export var rand_time: int = 60
@export var rand_length: float = 300

var is_critical_hit:bool = false
var is_fire_hit:bool = false
var is_explosion_hit:bool = false
var is_poison_hit:bool = false
var is_weak_hit: bool = false

var ACCELERATION:float

var hurt_damage:int = 0
var hurt_knockback:int = 0
var hurt_direction:Vector2

var enemy_body:Array = []
var body_part: Array = []

var player: Node

var can_shoot: bool = true

var aim_end: bool = false

var distance : float = 0
var distance_t: float = 0

var dir_v: Vector2 = Vector2.ZERO

var aim_and_move_speed: int
var shoot_and_move_speed: int

var move_mod:int = 0

var dir_num: int = 0

var in_knockback: bool = false

var is_idle: int = 1

var knockback_time: int = 0

var flash_time: int = 0

@export var shoot_cd_time: int = 40
@export var aim_time: int = 20

var decision_time: int = 5

@onready var shoot_cd: int = shoot_cd_time
var aim: int = 0

var now_rand_time: int = 0
var now_v: float = 0
var dir_p: Vector2 = Vector2.ZERO
var tilemap: Node
var target_position: Vector2 = Vector2.ZERO

@onready var sprite_2d = $Graphics/TankGraphics
@onready var graphics = $Graphics
@onready var enemy_buff_manager = $EnemyBuffManager
@onready var buff_box = $%BuffBox
@onready var gun = $Graphics/Gun
@onready var collision_shape_2d = $CollisionShape2D
@onready var tank_turret: Sprite2D = %tank_turret
@onready var tank_body: Sprite2D = %tank_body
@onready var area_2d: Area2D = $Area2D
@onready var weak_part: Area2D = $WeakPart
@onready var animation_player: AnimationPlayer = $Graphics/TankGraphics/AnimationPlayer
@onready var bullet_smoke: PackedScene = preload("res://script/explosion_damage.tscn")
@onready var weak_shape_2d: CollisionShape2D = $WeakPart/CollisionShape2D

func _ready():
	enemy_body.clear()
	player = get_tree().get_first_node_in_group("Player")
	tilemap = get_tree().get_first_node_in_group("Map")
	is_knockback.connect(body_in_knockback)
	PoolManager.add_pool(pool_id, self)

func idle_state():
	is_idle = 1
	enemy_body.clear()
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	self.visible = false
	self.global_position = Vector2.ZERO
	animation_player.play("RESET")
	collision_shape_2d.set_deferred("disabled",true)
	weak_shape_2d.set_deferred("disabled",true)
	enemy_buff_manager.clear_all_buff()
	set_physics_process(false)

func active_state():
	is_idle = 0
	stats.spawn_hp()
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	can_shoot = true
	aim_end = false
	animation_player.play("new_animation")
	move_mod = 0
	target_position = global_position
	self.visible = true
	collision_shape_2d.set_deferred("disabled",false)
	weak_shape_2d.set_deferred("disabled",false)
	set_physics_process(true)

func time_count():
	
	if flash_time > 0:
		flash_time -= 1
		if flash_time <= 0:
			sprite_2d.material.set_shader_parameter("flash_opacity", 0)
			sprite_2d.material.set_shader_parameter("outline_color", Color(0,0,0))
	
	if now_rand_time > 0:
		now_rand_time -= 1
		if now_rand_time <= 0:
			rand_target_position()
	
	if aim > 0:
		aim -= 1
		if aim <= 0:
			can_shoot = true
	
	if shoot_cd > 0:
		shoot_cd -= 1
	
	if decision_time > 0:
		decision_time -= 1
		if decision_time <= 0:
			dir_v = get_distance_to_player()
			shoot_and_move_speed = shoot_and_move * stats.MAX_SPEED
			decision_time = 5
	
	if knockback_time > 0:
		knockback_time -= 1
		if knockback_time <= 0:
			body_end_knockback()

func body_in_knockback():
	in_knockback = true
	knockback_time = 5

func body_end_knockback():
	in_knockback = false

func tick_physics(state: State, delta: float) -> void:
	if is_idle == 1:
		return
	
	ACCELERATION = stats.MAX_SPEED / stats.SPEED_TIME
	
	if enemy_body.size() != 0:
		for i in enemy_body:
			i.velocity += i.stats.weigth_mult * (i.global_position - self.global_position).normalized() * stats.MAX_SPEED / max(0.5, i.global_position.distance_to(self.global_position))
	
	if player != null:
		tank_turret.v = face_to_player().angle()
		gun.rotation = tank_turret.now_rotation
		shoot_bullet()
	
	box_around(tank_body.now_rotation)
	
	match state:
		
		State.IDLE:
			tank_body.v = now_v
			move(delta, ACCELERATION, 10)
		
		State.SHOOTING:
			move(delta, ACCELERATION, shoot_and_move_speed)
		
		State.AIMING:
			move(delta, ACCELERATION, aim_and_move_speed)
		
		State.RUNNING:
			tank_body.v = velocity.angle()
			move(delta, ACCELERATION, stats.MAX_SPEED)
		
		State.TURNING:
			tank_body.v = now_v
			move(delta, ACCELERATION, 0)

func box_around(now_rotation: float):
	collision_shape_2d.position = Vector2( 11.5, 0).rotated(now_rotation)
	collision_shape_2d.rotation = now_rotation
	area_2d.rotation = now_rotation
	weak_part.rotation = now_rotation

func on_dead():
	collision_shape_2d.set_deferred("disabled",true)
	weak_shape_2d.set_deferred("disabled",true)
	can_shoot = false
	animation_player.play("death_anim")
	await animation_player.animation_finished
	add_player_explosion()
	GameEvents.emit_enemy_dead_position(self.global_position)
	idle_state.call_deferred()

func add_player_explosion():
	
	var ins = PoolManager.get_pool("player_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = bullet_smoke.instantiate()
		add_ins = true
	
	ins.global_position = self.global_position
	ins.explosion_damage = 50 * stats.Enemy_damage_mult
	ins.explosion_knockback = stats.Enemy_Knockback
	ins.explosion_range = 6
	
	ins.active_state()
	if add_ins == true:
		get_tree().get_first_node_in_group("BulletRoot").add_child(ins)
	ins.is_explosion()

func face_to_player():
	if player != null and self.position.distance_to(player.position) > 5:
		return (player.global_position - global_position).normalized()
	return Vector2.ZERO

func get_distance_to_player():
	if player == null:
		return Vector2.ZERO
	distance = self.global_position.distance_to(player.position)
	if distance > shoot_range:
		move_mod = 0
		return (player.global_position - global_position).normalized()
	elif distance < back_range:
		move_mod = 0
		return (global_position - player.global_position).normalized()
	else:
		distance_t = self.global_position.distance_to(target_position)
		if distance_t > 40:
			move_mod = 3
			return (target_position - global_position).normalized()
		else:
			if now_rand_time <= 0:
				now_rand_time = rand_time
			turning_mod.emit()
			return Vector2.ZERO

func _shootAnim():
	for sprite_2d in tank_turret.get_children():
		var tween = get_tree().create_tween().set_parallel(true)
		tween.tween_property(sprite_2d, "scale", Vector2(sprite_2d.scale.x,sprite_2d.scale.y), 0.3).from(Vector2(sprite_2d.scale.x - 0.15, sprite_2d.scale.y + 0.4))

func shoot_bullet():
	if shoot_cd <= 0 and can_shoot == true:
		_shootAnim()
		gun.gun_shot()
		shoot_cd = shoot_cd_time

func move(delta: float, ACCELERATION: float ,MAX_SPEED: float ) -> void:
	
	var direction = dir_v
	dir_p = face_to_player()
	
	if stats.hp != 0:
	
		velocity.x = move_toward(velocity.x, direction.x * MAX_SPEED, ACCELERATION * delta)
		velocity.y = move_toward(velocity.y, direction.y * MAX_SPEED, ACCELERATION * delta)
		
	else:
		velocity = Vector2.ZERO
	
	move_and_slide()

func get_next_state(state: State) -> State:
	
	var is_still := velocity.x == 0 and velocity.y == 0
	if stats.hp == 0 :
		return State.IDLE
	
	match state:
		
		State.IDLE:
			if move_mod == 5:
				return State.TURNING
			if move_mod == 2:
				return State.AIMING
			if move_mod == 3:
				return State.RUNNING
		
		State.SHOOTING:
			if move_mod == 5:
				return State.TURNING
			if can_shoot == false and aim_end == false:
				if move_mod == 0:
					return State.RUNNING
				return State.IDLE
			
		State.AIMING:
			if move_mod == 5:
				return State.TURNING
			if move_mod == 0:
				return State.IDLE
			if can_shoot == true and aim <= 0:
				return State.SHOOTING
			
		State.RUNNING:
			if move_mod == 2:
				return State.AIMING
			if is_still:
				move_mod = 0
				return State.IDLE
			
		State.TURNING:
			if abs(fposmod(tank_body.now_rotation - now_v + PI, PI * 2) - PI) < 0.01:
				move_mod = 0
				return State.IDLE
			
	return state
	
func transition_state(from:State, to: State) -> void:
	
	match to:
		State.IDLE:
			now_v = face_to_player().angle()
		
		State.SHOOTING:
			pass
		
		State.AIMING:
			dir_num = randi_range(0,1)
			rand_aim_and_move_speed()
			surround_player()
			aim = aim_time
		
		State.RUNNING:
			pass
		
		State.TURNING:
			pass
		
		State.DEAD:
			pass

func _coin_drops():
	var coin_drops = PoolManager.get_pool("coins")
	if coin_drops == null or coin_drops.is_idle == 0:
		coin_drops = coin.instantiate()
		get_tree().get_first_node_in_group("CoinRoot").add_child(coin_drops)
	
	coin_drops.global_position = self.global_position
	coin_drops.coin = self.stats.Enemy_coin
	coin_drops.pick_up = self.stats.coin_pick
	coin_drops.active_state()

func _hurt_flash():
	sprite_2d.material.set_shader_parameter("flash_opacity", 1)
	sprite_2d.material.set_shader_parameter("outline_color", Color(2,2,2))
	flash_time = 1

func _on_damage():
	GameEvents.emit_enemy_hit_position(self)
	
	if hurt_damage != 0:
		stats.hp -= max(1, ( hurt_damage * stats.global_hurt_damage - stats.hurt_resis ))
		hurt_damage = 0
		_hurt_flash()
	
	if hurt_knockback != 0:
		var now_knockback = max(0, hurt_knockback - stats.knockback_resis )
		if now_knockback > 0:
			self.velocity = hurt_direction * now_knockback
		hurt_knockback = 0
	
	SoundManager.play_sfx("HurtSounds")

func rand_target_position():
	var ran = RandomNumberGenerator.new()
	var rand_position_num = ran.randi_range(0,len(tilemap.get_used_cells(0) ) ) - 5
	var rand_position = tilemap.map_to_local(tilemap.get_used_cells(0)[rand_position_num])
	while rand_position.distance_to(player.global_position) > rand_length:
		rand_position_num = ran.randi_range(0,len(tilemap.get_used_cells(0) ) ) - 5
		rand_position = tilemap.map_to_local(tilemap.get_used_cells(0)[rand_position_num])
	target_position = rand_position
	now_v = (target_position - global_position).normalized().angle()

func rand_aim_and_move_speed():
	var num:float = randf_range(0,aim_and_move)
	if num < 0.3 :
		num = 0
	aim_and_move_speed = num * stats.MAX_SPEED

func surround_player():
	var num = randf_range(0,100)
	if num < surround_tendency:
		aim = surround_time
		aim_and_move_speed = stats.MAX_SPEED

func _on_is_hurt():
	if is_idle == 1:
		return
	_on_damage()

func _on_enemy_stats_is_dead():
	_coin_drops.call_deferred()
	on_dead.call_deferred()

func _on_area_2d_body_entered(body):
	if is_idle == 1:
		return
	if body.is_in_group("Enemy")  and !enemy_body.has(body) and body != self and !body.is_in_group("EnemyPart"):
		enemy_body.append(body)
	
	if body.is_in_group("Enemy") and body != self and !body.is_in_group("EnemyPart"):
		var collosion_direction = (self.position - body.position).normalized()
		self.velocity += stats.weigth_mult * collosion_direction * stats.MAX_SPEED / 2

func _on_area_2d_body_exited(body):
	if is_idle == 1:
		return
	if body.is_in_group("Enemy")  and enemy_body.has(body):
		enemy_body.remove_at(enemy_body.find(body))
		if in_knockback == false:
			body.velocity = velocity.limit_length(body.stats.MAX_SPEED)

func _on_gun_shoot_end():
	aim_end = false


func _on_turning_mod() -> void:
	if tank_body.now_rotation != now_v:
		move_mod = 5


func _on_weak_part_body_entered(body: Node2D) -> void:
	if body.is_in_group("PlayerBullet"):
		hurt_damage = body.bullet_damage * 10
		is_critical_hit = true
		is_weak_hit = true
		is_hurt.emit()
		body.kill_time = 0
		body._on_bullet_kill_timer_timeout()
		GameEvents.emit_enemy_body(self,body)
		if body.is_player_shoot == true:
			GameEvents.emit_player_bullet_hit_enemy(body)
			GameEvents.emit_player_critical_hit_enemy(self)
		if stats.hp <= body.bullet_damage:
			GameEvents.emit_player_bullet_kill_enemy(body)
