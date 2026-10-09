class_name SummonedBullet
extends HitBox

signal in_idle

@export var pool_id: String = "normal_bullet"
@export var can_r: bool = false
@export var r_speed: int = 50
@export var has_line: bool = false

var acceleration: Vector2 = Vector2.ZERO
var target_position: Vector2

@onready var bullet_smoke: PackedScene = preload("res://scenes/bullet/bullet_smoke_2.tscn")
@onready var collision_shape_2d = $CollisionShape2D
@onready var ray_cast_2d = $RayCast2D

var penetrate: int = 1 #穿透值
var direction: Vector2 = Vector2.RIGHT
var speed: int = 300:
	set(v):
		speed = v
		_refresh_ray_length()
var collision_num: int = 0 #反弹次数
var kill_time: int = 110
var is_ready: bool = false
var line: Line2D
var line_2: Line2D

var velocity: Vector2

var is_player_shoot: bool = false

var is_idle: int = 1

var _shape_gen: int = 0

var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	direction = Vector2.RIGHT.rotated(global_rotation)
	velocity = direction * speed
	PoolManager.add_pool(pool_id,self)
	manages_own_hits = true
	_setup_self_hits()
	if has_line:
		line = $Line
		line_2 = $Line2
		line.life_timer = 4
		line_2.life_timer = line.life_timer
		line.scale_mult = player.stats.bullet_scale
		line_2.scale_mult = player.stats.bullet_scale
		line.update_width()
		line_2.update_width()
	
	is_on_ready()

func idle_state():
	if is_idle == 0:
		ExtensionHooks.notify(ExtensionHooks.on_projectile_despawned, [self])
	is_idle = 1
	set_physics_process(false)
	if GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.disconnect(_on_bullet_kill_timer_timeout)
	_clear_self_hits()
	_request_shape_disabled(true)
	in_idle.emit()
	can_r = false
	target_position = Vector2.ZERO
	ray_cast_2d.enabled = false
	self.visible = false
	self.global_position = Vector2.ZERO
	self.velocity = Vector2.ZERO
	if has_line:
		line.is_idle = true
		line_2.is_idle = true
		line.reset()
		line_2.reset()

func is_on_ready():
	is_ready = true
	active_state()

func active_state():
	if is_ready == false:
		return
	
	is_idle = 0
	set_physics_process(true)
	acceleration = Vector2.ZERO
	_clear_self_hits()
	if !GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.connect(_on_bullet_kill_timer_timeout)
	direction = Vector2.RIGHT.rotated(global_rotation)
	rotation = direction.angle()
	ray_cast_2d.enabled = true
	_request_shape_disabled(false)
	self.velocity = direction * speed
	self.visible = true
	if has_line:
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

func apply_penetrate_dealt():
	var cb: Callable = func(victim: Node, _actual_damage: float):
		damage_data.knockback_direction = (victim.global_position - player.global_position).normalized()
		bulletSmoke(global_position)
		penetrate -= victim.stats.penetrate_resis
		if penetrate <= 0:
			if collision_num > 0:
				direction = Vector2.RIGHT.rotated(global_rotation + randf_range(0.7, 1.3) * PI)
				velocity = direction * speed
				collision_num -= 1
			else:
				GameEvents.emit_summoned_bullet_free_position(self.global_position)
				idle_state()
	damage_data.on_damage_dealt.append(cb)

func _physics_process(delta):
	
	if is_idle == 1:
		return
	
	_tick_self_hits(delta)
	
	if ray_cast_2d.is_colliding():
		var collider = ray_cast_2d.get_collider()
		if collider.is_in_group("BulletWall"):
			var collision_position: Vector2 = ray_cast_2d.get_collision_point()
			global_position = collision_position
			if collision_num > 0:
				collision_num -= 1
				velocity = IsoProjection.bounce(velocity, ray_cast_2d.get_collision_normal())
				rotation = velocity.angle()
			
			else:
				bulletSmoke(collision_position)
				GameEvents.emit_summoned_bullet_free_position(self.global_position)
				idle_state()
	
	if can_r == true:
		r_move(delta)
	
	global_position += velocity * delta

func r_move(delta: float):
	direction = (target_position - self.global_position).normalized()
	acceleration += (direction * speed - velocity).normalized() * r_speed
	velocity += acceleration * delta
	velocity = velocity.limit_length(speed)
	if velocity != Vector2.ZERO:
		rotation = velocity.angle()

func smoke_add():
	
	var ins = PoolManager.get_pool("bullet_smoke_2")
	if ins == null or ins.is_idle == 0:
		ins = bullet_smoke.instantiate()
		get_parent().add_child(ins)
	
	return ins

func bulletSmoke(smoke_position: Vector2):
	var ins = smoke_add()
	ins.global_position = smoke_position
	ins.scale = self.scale
	ins.smoke_anim()

# speed 变更时同步射线长度：避免“active_state 之后才设 speed”导致穿墙/漏判。
func _refresh_ray_length() -> void:
	if ray_cast_2d != null:
		ray_cast_2d.target_position.x = speed * 0.0167

# 统一形状启停出口：自增代数并延迟写入，作废同帧残留的旧延迟调用，
# 避免在物理 query flush 期直接写 Area2D 形状（area_set_shape_disabled 报错）。
func _request_shape_disabled(value: bool) -> void:
	_shape_gen += 1
	call_deferred("_set_shape_disabled_guarded", value, _shape_gen)

func close_shape():
	pass

# gen 校验：作废「命中后回池、又在同帧被复用」时残留的延迟关闭。
func _set_shape_disabled_guarded(value: bool, gen: int) -> void:
	if gen != _shape_gen:
		return
	collision_shape_2d.disabled = value

func _on_bullet_kill_timer_timeout():
	if is_idle == 1:
		return
	
	if kill_time > 0:
		kill_time -= 1
	else:
		var ins = smoke_add()
		ins.global_position = global_position
		ins.scale = self.scale
		ins.smoke_anim()
		GameEvents.emit_summoned_bullet_free_position(self.global_position)
		idle_state()
