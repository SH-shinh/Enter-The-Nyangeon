extends CharacterBody2D

signal enemy_body_get(body: Node)
signal in_idle

@export var can_r: bool = false
@export var r_speed: int = 50
@export var fall_value: float = 980
@export var life_time: int = 4
@export var base_explosion_range: float = 1

var acceleration: Vector2 = Vector2.ZERO
var target_position: Vector2

@onready var bullet_smoke: PackedScene = preload("res://script/explosion_damage.tscn")
@onready var line = $Line
@onready var line_2 = $Line2
@onready var fall_timer = $FallTimer

var is_ready: bool = false

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
var mouse_length: float
var fly_time: float
var fly_num: float
var target: Vector2

var is_idle: int = 1

var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	fall_timer.timeout.connect(bullet_explosion)
	direction = Vector2.RIGHT.rotated(global_rotation)
	velocity = direction * speed
	PoolManager.add_pool("player_bullet",self)
	if line != null:
		line.life_timer = life_time
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
	in_idle.emit()
	is_critical = false
	is_player_shoot = false
	can_r = false
	target_position = Vector2.ZERO
	mouse_length = 0
	fall_timer.stop()
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
	direction = Vector2.RIGHT.rotated(global_rotation)
	self.velocity = direction * speed
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
	count_fly_time()

func count_fly_time():
	if mouse_length == 0:
		if target_position != Vector2.ZERO:
			mouse_length = self.global_position.distance_to(target_position)
		else:
			mouse_length = randi_range(50,150)
	
	fly_time = mouse_length / speed
	
	if kill_time <= 0:
		kill_time = 1
	
	if fly_time > (float(kill_time) / 10):
		mouse_length = (float(kill_time) / 10) * speed
		fly_time = mouse_length / speed
	if fly_time != 0:
		fall_timer.wait_time = fly_time
	fall_timer.start()
	fly_num = PI / fly_time
	target = direction * mouse_length
	velocity.x = target.x / fly_time
	velocity.y = target.y / fly_time
	velocity.y -= fall_value * fly_time / 2

func fly_move(delta: float):
	velocity.y += fall_value * delta

func _physics_process(delta):
	if is_idle == 1:
		return
	
	
	if can_r == true:
		r_move(delta)
	else:
		fly_move(delta)
	
	move_and_slide()
	rotation = velocity.normalized().angle()

func r_move(delta: float):
	direction = (target_position - self.global_position).normalized() * speed
	acceleration += (direction - velocity).normalized() * r_speed
	velocity += acceleration * delta
	velocity = velocity.limit_length(speed)

func bulletSmoke(collisionResult):
	var ins = bullet_smoke.instantiate()
	get_parent().add_child(ins)
	ins.global_position = collisionResult.get_position()
	ins.rotation = collisionResult.get_normal().angle()

func bullet_explosion():
	
	var ins = PoolManager.get_pool("player_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = bullet_smoke.instantiate()
		add_ins = true
	
	ins.global_position = self.global_position
	ins.explosion_damage = bullet_damage * player.stats.explosion_damage
	ins.explosion_knockback = bullet_knockback
	ins.explosion_range = max(1, player.stats.explosion_range * 0.8) * max(1, player.stats.bullet_scale * 0.6) * base_explosion_range
	ins.is_critical = is_critical
	ins.is_player_bullet = true
	ins.is_player_shoot = is_player_shoot
	
	ins.active_state()
	if add_ins == true:
		get_tree().get_first_node_in_group("BulletRoot").add_child(ins)
	ins.is_small_explosion()
	
	GameEvents.emit_player_bullet_explosion(self.global_position)
	
	if collision_num > 0:
		collision_num -= 1
		mouse_length /= 1.2
		speed /= 1.2
		direction = Vector2(randf_range(-1,1), randf_range(-1,1))
		count_fly_time()
		GameEvents.emit_player_bullet_collision(self)
	else:
		GameEvents.emit_player_bullet_free_position(self.global_position)
		idle_state()

func _on_bullet_kill_timer_timeout():
	if is_idle == 1:
		return
	
	if kill_time > 0:
		kill_time -= 1
	else:
		bullet_explosion()
	
