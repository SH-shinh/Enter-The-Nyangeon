extends CharacterBody2D

signal enemy_body_get(body: Node)
signal in_idle

@export var can_r: bool = false
@export var r_speed: int = 50
var acceleration: Vector2 = Vector2.ZERO
var target_position: Vector2

@export var enemy_buff: Buff

@onready var bullet_smoke: PackedScene = preload("res://scenes/bullet/bullet_smoke.tscn")
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D
@onready var gpu_particles_2d_2: GPUParticles2D = $GPUParticles2D2
@onready var area_2d = $Area2D
@onready var collision_shape_2d = $Area2D/CollisionShape2D
@onready var collision_shape_2d_2 = $CollisionShape2D


var is_ready: bool = false
var ACCELERATION: float
var penetrate: int = 1 #穿透值
var direction: Vector2 = Vector2.RIGHT
var speed: int = 300
var collision_num: int = 0 #反弹次数
var bullet_damage: int = 0
var bullet_knockback: int = 0
var kill_time: int = 110
var append_damage: int = 0 #追加伤害
var is_critical: bool = false
var value: Array = [1,1,1]
@export var is_player_shoot: bool = false
@export var slow_down: bool = false
@export var slow_time: float = 0

var can_block: bool = true

var is_idle: int = 1

var cd_time:int = 0

var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	direction = Vector2.RIGHT.rotated(global_rotation)
	velocity = direction * speed
	PoolManager.add_pool("player_bullet",self)
	
	is_on_ready()

func is_on_ready():
	is_ready = true
	active_state()

func idle_state():
	is_idle = 1
	if GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.disconnect(_on_bullet_kill_timer_timeout)
	collision_shape_2d.set_deferred("disabled",true)
	gpu_particles_2d.emitting = false
	gpu_particles_2d_2.emitting = false
	in_idle.emit()
	is_critical = false
	is_player_shoot = false
	can_r = false
	target_position = Vector2.ZERO
	self.visible = false
	self.global_position = Vector2.ZERO
	self.velocity = Vector2.ZERO

func active_state():
	
	if is_ready == false:
		return
	
	is_idle = 0
	if !GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.connect(_on_bullet_kill_timer_timeout)
	collision_shape_2d.set_deferred("disabled",false)
	gpu_particles_2d.emitting = true
	gpu_particles_2d_2.emitting = true
	gpu_particles_2d.restart()
	gpu_particles_2d_2.restart()
	direction = Vector2.RIGHT.rotated(global_rotation)
	self.velocity = direction * speed
	if slow_down == true:
		ACCELERATION = speed / slow_time
	self.visible = true

func _physics_process(delta):
	
	if is_idle == 1:
		return
	
	var collisionResult = get_last_slide_collision()
	if collisionResult :
		if collision_num > 0:
			collision_num -= 1
			direction = velocity.bounce(collisionResult.get_normal()).normalized()
			#close_shape_2()
			
		
		else:
			bulletSmoke(collisionResult)
			GameEvents.emit_player_bullet_free_position(self.global_position)
			idle_state()
	
	
	
	if slow_down == true:
		var v_value = move_toward(velocity.length(), 0, ACCELERATION * delta)
		velocity = direction * v_value
	
	if can_r == true:
		r_move(delta)
	
	move_and_slide()
	rotation = velocity.normalized().angle()

func r_move(delta: float):
	direction = (target_position - self.global_position).normalized() * speed
	acceleration += (direction - velocity).normalized() * r_speed
	velocity += acceleration * delta
	velocity = velocity.limit_length(speed)

func smoke_add():
	
	var ins = PoolManager.get_pool("bullet_smoke_1")
	if ins == null or ins.is_idle == 0:
		ins = bullet_smoke.instantiate()
		get_parent().add_child(ins)
	
	return ins

func bulletSmoke(collisionResult):
	var ins = smoke_add()
	
	ins.global_position = collisionResult.get_position()
	ins.rotation = collisionResult.get_normal().angle()
	ins.smoke_anim()


func _on_area_2d_body_entered(body):
	if is_idle == 1:
		return
	
	if body.is_in_group("Enemy"):
		
		enemy_body_get.emit(body)
		var hit_direction = (body.position - player.position).normalized()
	
		GameEvents.emit_enemy_body(body,self)
		if is_player_shoot == true:
			GameEvents.emit_player_bullet_hit_enemy(self)
			if is_critical == true:
				GameEvents.emit_player_critical_hit_enemy(body)
				body.is_critical_hit = true
		body.hurt_damage = bullet_damage * player.stats.dot_damage
		body.hurt_knockback = bullet_knockback
		body.hurt_direction = hit_direction
		body.is_fire_hit = true
		
		penetrate = max(0, penetrate - body.stats.penetrate_resis)
		
		if body.stats.hp <= bullet_damage:
			GameEvents.emit_player_bullet_kill_enemy(self)
		
		var ins = smoke_add()
		ins.global_position = position
		ins.rotation = direction.angle() + PI
		ins.smoke_anim()
		
		body.emit_signal("is_hurt")
		
		body.enemy_buff_manager.apply_buff(enemy_buff, value)
		
		close_shape()
		
		if can_block == true:
			if penetrate <= 0:
				
				if collision_num > 0:
					direction = Vector2.RIGHT.rotated(global_rotation + randf_range(0.7, 1.3) * PI)
					velocity = direction * speed
					collision_num -= 1
					
					close_shape()
					
					
				else:
					GameEvents.emit_player_bullet_free_position(self.global_position)
					idle_state()
		

func time_count():
	if cd_time > 0:
		cd_time -= 1
		if cd_time <= 0:
			if GameEvents.global_time_count.is_connected(time_count):
				GameEvents.global_time_count.disconnect(time_count)
			collision_shape_2d.set_deferred("disabled",false)
			collision_shape_2d_2.set_deferred("disabled",false)

func close_shape():
	collision_shape_2d.set_deferred("disabled",true)
	cd_time = 1
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)

func close_shape_2():
	collision_shape_2d_2.set_deferred("disabled",true)
	cd_time = 1
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)


func _on_bullet_kill_timer_timeout():
	if is_idle == 1:
		return
	
	if kill_time > 0:
		kill_time -= 1
	else:
		var ins = smoke_add()
		ins.global_position = global_position
		ins.rotation = rotation
		ins.smoke_anim()
		GameEvents.emit_player_bullet_free_position(self.global_position)
		idle_state()
	
