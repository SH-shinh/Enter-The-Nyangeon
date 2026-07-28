extends CharacterBody2D

signal penetrate_changed

var direction: Vector2 = Vector2.RIGHT
var speed: int = 100
var bullet_damage: int = 1
var knockback: int = 200
var collision_num: int = 0 #反弹次数
var penetrate: int = 0
var kill_time: float = 110
var decay_time: float = 0
var decay_speed: int = 0
var is_decay: bool = false
var explosion_range: float = 1
var speed_time: float = 5
var accel: float
var dir_v: Vector2 = Vector2.ZERO
var player: Node
var shoot_bullet_num: int = 0

var is_idle: int = 1
var is_ready: bool = false

@export var pool_id: String
@export var r_speed: int = 1
var acceleration: Vector2 = Vector2.ZERO

@onready var missile_explosion:PackedScene = preload("res://scenes/bullet/enemy_explosion_damage.tscn")

@onready var enemy_missile = $CanvasGroup/EnemyMissile
@onready var marker_2d = $Marker2D
@onready var explosion_position = $Marker2D/ExplosionPosition
@onready var gpu_particles_2d = $Marker2D/GPUParticles2D

@onready var now_penetrate: int = penetrate:
	set(v):
		v = clamp(v, 0, penetrate)
		if now_penetrate == v:
			return
		now_penetrate = v
		penetrate_changed.emit()

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	penetrate_changed.connect(bullet_kill)
	PoolManager.add_pool(pool_id,self)
	is_on_ready()

func is_on_ready():
	is_ready = true
	active_state()

func idle_state():
	is_idle = 1
	if GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.disconnect(_on_bullet_kill_timer_timeout)
	if GameEvents.global_time_count.is_connected(_on_bullet_decay_timer_timeout):
		GameEvents.global_time_count.disconnect(_on_bullet_decay_timer_timeout)
	self.visible = false
	self.global_position = Vector2.ZERO
	self.velocity = Vector2.ZERO

func active_state():
	
	if is_ready == false:
		return
	
	is_idle = 0
	if !GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.connect(_on_bullet_kill_timer_timeout)
	gpu_particles_2d.restart()
	direction = Vector2.RIGHT.rotated(global_rotation)
	self.velocity = direction * speed
	self.visible = true
	set_deferred("rotation", 0)

func _physics_process(delta):
	
	if is_idle == 1:
		return
	
	var collisionResult = get_last_slide_collision()
	
	if is_decay == true and speed >= 0:
		speed -= decay_speed
		velocity = direction * max(0,speed)
	
	if collisionResult :
		if collision_num > 0:
			collision_num -= 1
			velocity = velocity.bounce(collisionResult.get_normal())
		
		else:
			add_explosion.call_deferred()
	
	dir_v = (player.global_position - self.global_position).normalized() * speed
	acceleration += (dir_v - velocity).normalized() * r_speed
	velocity += acceleration * delta
	velocity = velocity.limit_length(speed)
	
	move_and_slide()
	enemy_missile.v = velocity.normalized().angle()
	marker_2d.rotation = enemy_missile.v

func add_explosion():
	
	var ins = PoolManager.get_pool("enemy_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = missile_explosion.instantiate()
		add_ins = true
	
	ins.global_position = explosion_position.global_position
	ins.explosion_damage = bullet_damage
	ins.explosion_knockback = 2 * knockback
	ins.explosion_range = explosion_range
	
	ins.active_state()
	if add_ins == true:
		get_tree().get_first_node_in_group("SELayer").add_child(ins)
	ins.is_explosion()
	idle_state()

func bullet_kill():
	pass

func _on_bullet_kill_timer_timeout():
	if is_idle == 1:
		return
	
	if kill_time > 0:
		kill_time -= 1
	else:
		add_explosion.call_deferred()

func _on_bullet_decay_timer_timeout():
	
	if is_idle == 1:
		return
	
	if decay_time > 0:
		decay_time -= 1
	else:
		is_decay = true


func _on_hit_box_body_entered(body):
	if body.is_in_group("Player"):
		if body.invincible_frame.time_left > 0:
			return
		add_explosion.call_deferred()
