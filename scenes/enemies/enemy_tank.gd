extends Enemy
class_name EnemyTank

signal turning_mod

enum State {
	IDLE,
	SHOOTING,
	AIMING,
	RUNNING,
	TURNING,
	DEAD,
}

@export var shoot_range: int
@export var back_range: int
@export var aim_and_move: float
@export var shoot_and_move: float
@export_range(0,100) var surround_tendency: int
@export var surround_time: int
@export var rand_time: int = 60
@export var rand_length: float = 300

var can_shoot: bool = true

var _recoil_tween: Tween
var _recoil_base: Dictionary = {}

var aim_end: bool = false

var distance : float = 0
var distance_t: float = 0

var dir_v: Vector2 = Vector2.ZERO

var aim_and_move_speed: int
var shoot_and_move_speed: int

var move_mod:int = 0

var dir_num: int = 0

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

@onready var buff_box = $%BuffBox
@onready var gun = $Graphics/Gun
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
	_target_cache = null
	_target_cache_frame = -1
	PoolManager.unregister_active_enemy(self)
	enemy_body.clear()
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	self.visible = false
	self.global_position = Vector2.ZERO
	animation_player.play("RESET")
	collision_shape_2d.set_deferred("disabled",true)
	weak_shape_2d.set_deferred("disabled",true)
	enemy_buff_manager.clear_all_buff()
	if tank_body != null:
		tank_body.set_physics_process(false)
	if tank_turret != null:
		tank_turret.set_physics_process(false)
	set_physics_process(false)

func active_state():
	is_idle = 0
	_target_cache = null
	_target_cache_frame = -1
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
	if tank_body != null:
		tank_body.set_physics_process(true)
	if tank_turret != null:
		tank_turret.set_physics_process(true)
	set_physics_process(true)
	create_damage_data()
	PoolManager.register_active_enemy(self)

func time_count():
	
	if flash_time > 0:
		flash_time -= 1
		if flash_time <= 0:
			if graphics != null:
				graphics.modulate = Color.WHITE
	
	if now_rand_time > 0:
		now_rand_time -= 1
		if now_rand_time <= 0:
			if not is_standby():
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
			if is_standby():
				dir_v = Vector2.ZERO
				move_mod = 0
			else:
				dir_v = get_distance_to_player()
			shoot_and_move_speed = int(shoot_and_move * stats.MAX_SPEED)
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

func _hurt_flash():
	if graphics != null:
		graphics.modulate = Color(2, 2, 2)
	flash_time = 1

func tick_physics(state: State, delta: float) -> void:
	if is_idle == 1:
		return
	
	ACCELERATION = stats.move_acceleration()
	
	apply_soft_collision()
	
	if get_target() != null:
		if not is_standby():
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
	ProjectileSpawner.spawn_core(
		bullet_smoke, "player_explosion", "BulletRoot", self, Faction.ENEMY_SIDE,
		self.global_position, 0.0, Vector2.ZERO,
		false, false, true,
		Callable(self, "_configure_explosion"),
		Callable(),
		Callable(self, "_post_explosion")
	)

func _configure_explosion(node: Node) -> void:
	node.damage_data = DamageData.fill(node.damage_data, {
		"damage": 50 * stats.Enemy_damage_mult,
		"knockback": stats.Enemy_Knockback,
		"type": GameTags.EXPLOSION_DAMAGE,
		"source": GameTags.NEUTRAL,
		"node": self,
	})
	node.explosion_range = 6

func _post_explosion(node: Node) -> void:
	node.is_explosion()

func face_to_player():
	var t := get_target()
	if t != null and self.position.distance_to(t.global_position) > 5:
		return (t.global_position - global_position).normalized()
	return Vector2.ZERO

func get_distance_to_player():
	var tp := get_target_position()
	distance = self.global_position.distance_to(tp)
	if distance > shoot_range:
		move_mod = 0
		return (tp - global_position).normalized()
	elif distance < back_range:
		move_mod = 0
		return (global_position - tp).normalized()
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
	if tank_turret.get_child_count() == 0:
		return
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	_recoil_tween = get_tree().create_tween().set_parallel(true)
	for sprite_local in tank_turret.get_children():
		var base: Vector2
		if _recoil_base.has(sprite_local):
			base = _recoil_base[sprite_local]
		else:
			base = sprite_local.scale
			_recoil_base[sprite_local] = base
		_recoil_tween.tween_property(sprite_local, "scale", base, 0.3).from(Vector2(base.x - 0.15, base.y + 0.4))

func shoot_bullet():
	if is_standby():
		return
	if shoot_cd <= 0 and can_shoot == true:
		_shootAnim()
		gun.gun_shot()
		shoot_cd = shoot_cd_time

func move(delta: float, acceleration_local: float ,MAX_SPEED: float ) -> void:
	
	direction = dir_v
	dir_p = face_to_player()
	
	if stats.hp != 0:
	
		velocity.x = move_toward(velocity.x, direction.x * MAX_SPEED, acceleration_local * delta)
		velocity.y = move_toward(velocity.y, direction.y * MAX_SPEED, acceleration_local * delta)
		
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
	
func transition_state(_from:State, to: State) -> void:
	
	match to:
		State.IDLE:
			if not is_standby():
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

func rand_target_position():
	if tilemap == null:
		return
	var cells: Array = tilemap.get_used_cells(0)
	if cells.is_empty():
		return
	var ran := RandomNumberGenerator.new()
	var anchor := get_target_position()
	var best_position: Vector2 = global_position
	var best_diff: float = INF
	var attempts := 0
	const MAX_ATTEMPTS := 20
	while attempts < MAX_ATTEMPTS:
		attempts += 1
		var idx := ran.randi_range(0, cells.size() - 1)
		var pos: Vector2 = tilemap.map_to_local(cells[idx])
		var diff: float = absf(pos.distance_to(anchor) - rand_length)
		if diff < best_diff:
			best_diff = diff
			best_position = pos
		if pos.distance_to(anchor) <= rand_length:
			best_position = pos
			break
	target_position = best_position
	now_v = (target_position - global_position).normalized().angle()

func rand_aim_and_move_speed():
	var num:float = randf_range(0,aim_and_move)
	if num < 0.3 :
		num = 0
	aim_and_move_speed = int(num * stats.MAX_SPEED)

func surround_player():
	var num = randf_range(0,100)
	if num < surround_tendency:
		aim = surround_time
		aim_and_move_speed = stats.MAX_SPEED

func _on_enemy_stats_is_dead():
	_coin_drops.call_deferred()
	on_dead.call_deferred()

func _on_gun_shoot_end():
	aim_end = false


func _on_turning_mod() -> void:
	if tank_body.now_rotation != now_v:
		move_mod = 5


func _on_weak_part_body_entered(body: Node2D) -> void:
	if body.is_in_group("PlayerBullet"):
		hurt_damage = body.bullet_damage * 10
