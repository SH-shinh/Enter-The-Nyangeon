extends CharacterBody2D

signal enemy_body_get(body: Node)
signal in_idle(bullet_body: Node)

@export var pool_id: String = "player_bullet"
@export var can_r: bool = false
@export var r_speed: int = 50
var acceleration: Vector2 = Vector2.ZERO
var target_position: Vector2

@onready var bullet_smoke: PackedScene = preload("res://scenes/bullet/bullet_smoke.tscn")
@onready var line = $Line
@onready var line_2 = $Line2
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
@export var is_player_shoot: bool = false
@export var slow_down: bool = false
@export var slow_time: float = 0

var is_idle: int = 1

var cd_time:int = 0

var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	direction = Vector2.RIGHT.rotated(global_rotation)
	velocity = direction * speed
	PoolManager.add_pool(pool_id,self)
	if line != null:
		line.life_timer = 4
		line_2.life_timer = line.life_timer
		line.scale_mult = player.stats.bullet_scale
		line_2.scale_mult = player.stats.bullet_scale
		line.update_width()
		line_2.update_width()
	
	is_on_ready()

func is_on_ready():
	is_ready = true
	active_state()

func idle_state():
	is_idle = 1
	if GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.disconnect(_on_bullet_kill_timer_timeout)
	collision_shape_2d.disabled = true
	in_idle.emit(self)
	is_critical = false
	is_player_shoot = false
	can_r = false
	target_position = Vector2.ZERO
	self.visible = false
	self.global_position = Vector2.ZERO
	self.velocity = Vector2.ZERO
	if line != null:
		line.is_idle = true
		line_2.is_idle = true
		line.reset()
		line_2.reset()

func active_state():
	
	if is_ready == false:
		return
	
	is_idle = 0
	if !GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.connect(_on_bullet_kill_timer_timeout)
	collision_shape_2d.disabled = false
	direction = Vector2.RIGHT.rotated(global_rotation)
	self.velocity = direction * speed
	if slow_down == true:
		ACCELERATION = speed / slow_time
	if line != null:
		line.reset()
		line_2.reset()
		line.is_idle = false
		line_2.is_idle = false
		line.life_timer = 4
		line_2.life_timer = line.life_timer
		line.scale_mult = player.stats.bullet_scale
		line_2.scale_mult = player.stats.bullet_scale
		line.update_width()
		line_2.update_width()
	self.visible = true

func _physics_process(delta):
	
	if is_idle == 1:
		return
	
	if slow_down == true:
		var v_value = move_toward(velocity.length(), 0, ACCELERATION * delta)
		velocity = direction * v_value
	
	var collisionResult = get_last_slide_collision()
	if collisionResult :
		if collision_num > 0:
			collision_num -= 1
			velocity = velocity.bounce(collisionResult.get_normal())
			GameEvents.emit_player_bullet_collision(self)
		
		else:
			bulletSmoke(collisionResult)
			GameEvents.emit_player_bullet_free_position(self.global_position)
			idle_state()
	
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
		body.hurt_damage = bullet_damage
		body.hurt_knockback = bullet_knockback
		body.hurt_direction = hit_direction
		penetrate = max(0, penetrate - body.stats.penetrate_resis)
		
		GameEvents.emit_enemy_body(body,self)
		if is_player_shoot == true:
			GameEvents.emit_player_bullet_hit_enemy(self)
			if is_critical == true:
				GameEvents.emit_player_critical_hit_enemy(body)
				body.is_critical_hit = true
		
		if body.stats.hp <= bullet_damage:
			GameEvents.emit_player_bullet_kill_enemy(self)
		
		var ins = smoke_add()
		ins.global_position = position
		ins.rotation = direction.angle() + PI
		ins.smoke_anim()
		
		body.emit_signal("is_hurt")
		
		close_shape()
		
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
	
