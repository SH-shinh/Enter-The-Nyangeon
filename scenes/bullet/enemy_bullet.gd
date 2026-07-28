extends CharacterBody2D

@export var smoke: PackedScene
@export var pool_id: String

signal penetrate_changed
signal bullet_idle(bullet: Node)

var direction: Vector2 = Vector2.RIGHT
var speed: int = 100
var bullet_damage: int = 1
var knockback: int = 200
var collision_num: int = 0 #反弹次数
var penetrate: int = 0
var kill_time: float = 110
var decay_time: float = 0
var decay_speed: int = 0
var shoot_bullet_num: int = 0
var is_decay: bool = false
var is_stop: bool = false

var ACCELERATION: float

var is_idle: int = 1
var is_ready: bool = false

@onready var now_penetrate: int = penetrate:
	set(v):
		v = clamp(v, 0, penetrate)
		if now_penetrate == v:
			return
		now_penetrate = v
		penetrate_changed.emit()

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D

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
	is_stop = false
	self.visible = false
	self.global_position = Vector2.ZERO
	self.velocity = Vector2.ZERO
	collision_shape_2d.disabled = true
	bullet_idle.emit(self)

func active_state():
	
	if is_ready == false:
		return
	
	is_idle = 0
	if !GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.connect(_on_bullet_kill_timer_timeout)
	
	direction = Vector2.RIGHT.rotated(global_rotation)
	now_penetrate = penetrate
	if decay_time != 0:
		if !GameEvents.global_time_count.is_connected(_on_bullet_decay_timer_timeout):
			GameEvents.global_time_count.connect(_on_bullet_decay_timer_timeout)
		ACCELERATION = speed / ((kill_time - decay_time) / 10)
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
	ins.smoke_anim()

func bulletSmoke(collisionResult):
	var ins = PoolManager.get_pool("bullet_smoke_2")
	if ins == null or ins.is_idle == 0:
		ins = smoke.instantiate()
		get_parent().add_child(ins)
	
	ins.global_position = collisionResult.get_position()
	ins.scale = self.scale
	ins.smoke_anim()

func is_stop_false():
	is_stop = false

func _physics_process(delta):
	
	if is_idle == 1:
		return
	
	var collisionResult = get_last_slide_collision()
	if is_stop == true:
		return
	
	if is_decay == true:
		var v_value = move_toward(velocity.length(), 0, ACCELERATION * delta)
		velocity = direction * v_value
	
	if collisionResult :
		if collision_num > 0:
			collision_num -= 1
			velocity = velocity.bounce(collisionResult.get_normal())
		
		else:
			bulletSmoke(collisionResult)
			idle_state()
	move_and_slide()

func bullet_clear():
	add_smoke()
	idle_state()

func bullet_kill():
	if now_penetrate <= 0:
		add_smoke()
		idle_state()

func _on_bullet_kill_timer_timeout():
	
	if is_idle == 1:
		return
	
	if kill_time > 0:
		kill_time -= 1
	else:
		add_smoke()
		idle_state()

func _on_bullet_decay_timer_timeout():
	
	if is_idle == 1:
		return
	
	if decay_time > 0:
		decay_time -= 1
	else:
		is_decay = true
