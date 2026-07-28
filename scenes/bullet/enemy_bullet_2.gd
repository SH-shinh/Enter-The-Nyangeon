extends CharacterBody2D

@export var smoke: PackedScene
@export var pool_id: String
@export var shrapnel_scale: float = 0.6
@export var shoot_bullet_num: int = 0

signal penetrate_changed

var direction: Vector2 = Vector2.RIGHT
var speed: int = 100
var bullet_damage: int = 1
var knockback: int = 200
var collision_num: int = 0 #反弹次数
var penetrate: int = 0
var kill_time: float = 11
var decay_time: float = 0
var decay_speed: int = 0
var is_decay: bool = false
var firest_speed: int = 0

var ACCELERATION: float

var is_idle: int = 1
var is_ready: bool = false

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var bullet_launcher = $BulletLauncher
@onready var now_penetrate: int = penetrate:
	set(v):
		v = clamp(v, 0, penetrate)
		if now_penetrate == v:
			return
		now_penetrate = v
		penetrate_changed.emit()

func _ready():
	GameEvents.boss_round_end.connect(bullet_clear)
	GameEvents.round_end.connect(bullet_clear)
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
	is_decay = false
	decay_time = 0
	self.visible = false
	self.global_position = Vector2.ZERO
	self.velocity = Vector2.ZERO
	collision_shape_2d.disabled = true

func active_state():
	
	if is_ready == false:
		return
	
	is_idle = 0
	if !GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.connect(_on_bullet_kill_timer_timeout)
	firest_speed = speed
	now_penetrate = penetrate
	if decay_time != 0:
		if !GameEvents.global_time_count.is_connected(_on_bullet_decay_timer_timeout):
			GameEvents.global_time_count.connect(_on_bullet_decay_timer_timeout)
		ACCELERATION = speed / ((kill_time - decay_time) / 10)
	direction = Vector2.RIGHT.rotated(global_rotation)
	self.velocity = direction * speed
	self.visible = true
	collision_shape_2d.disabled = false

func add_smoke():
	
	var ins = PoolManager.get_pool("bullet_smoke_2")
	if ins == null or ins.is_idle == 0:
		ins = smoke.instantiate()
		get_parent().add_child(ins)
	
	ins.scale = self.scale
	ins.global_position = position
	ins.smoke_anim.call_deferred()

func bulletSmoke(collisionResult):
	var ins = PoolManager.get_pool("bullet_smoke_2")
	if ins == null or ins.is_idle == 0:
		ins = smoke.instantiate()
		get_parent().add_child(ins)
	
	ins.global_position = collisionResult.get_position()
	ins.scale = self.scale
	ins.smoke_anim.call_deferred()

func _physics_process(delta):
	
	if is_idle == 1:
		return
	
	var collisionResult = get_last_slide_collision()
	
	if is_decay == true:
		var v_value = move_toward(velocity.length(), 0, ACCELERATION * delta)
		velocity = direction * v_value
	
	if collisionResult :
		if collision_num > 0:
			collision_num -= 1
			velocity = velocity.bounce(collisionResult.get_normal())
		
		else:
			bullet_shoot()
			bulletSmoke(collisionResult)
			idle_state()
	move_and_slide()

func bullet_clear():
	add_smoke()
	idle_state()

func bullet_kill():
	if now_penetrate <= 0:
		bullet_shoot()
		add_smoke()
		idle_state.call_deferred()

func bullet_shoot():
	bullet_launcher.bullet_damage = bullet_damage
	bullet_launcher.bullet_penetrate = penetrate
	bullet_launcher.collision_num = collision_num
	bullet_launcher.kill_time = 110
	bullet_launcher.bullet_scale = shrapnel_scale
	for i in shoot_bullet_num:
		bullet_launcher.rotation = randf_range(-PI,PI)
		bullet_launcher.bullet_speed = firest_speed * randf_range(0.8,1.2)
		bullet_launcher.shoot_bullet()

func _on_bullet_kill_timer_timeout():
	
	if is_idle == 1:
		return
	
	if kill_time > 0:
		kill_time -= 1
	else:
		bullet_shoot()
		add_smoke()
		idle_state.call_deferred()

func _on_bullet_decay_timer_timeout():
	
	if is_idle == 1:
		return
	
	if decay_time > 0:
		decay_time -= 1
	else:
		is_decay = true
