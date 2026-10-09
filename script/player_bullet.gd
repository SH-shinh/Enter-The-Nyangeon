class_name PlayerBullet
extends HitBox

signal in_idle(bullet_body: Node)

var velocity: Vector2
var acceleration: Vector2 = Vector2.ZERO
var target_position: Vector2

@export var pool_id: String = "player_bullet"
@export var can_r: bool = false
@export var homing: bool = false
@export var homing_scan_interval: int = 3
@export var homing_range: float = 1400.0 # 子弹到目标距离超过此值不再锁定（≈ 地图对角）
@export var r_speed: int = 50

var is_ready: bool = false
var ACCELERATION: float
var penetrate: int = 1 #穿透值
var direction: Vector2 = Vector2.RIGHT
var speed: int = 300:
	set(v):
		speed = v
		_refresh_ray_length()
var collision_num: int = 0 #反弹次数
var kill_time: int = 110

var flight_time: float = 0.0

@export var slow_down: bool = false
@export var slow_time: float = 0

var is_idle: int = 1

var _shape_gen: int = 0

var _homing_target: Node = null
var _homing_scan_cd: int = 0

var player: Node

@onready var line = get_node_or_null("Line")
@onready var line_2 = get_node_or_null("Line2")
@onready var collision_shape_2d = $CollisionShape2D
@onready var bullet_smoke: PackedScene = preload("res://scenes/bullet/bullet_smoke.tscn")
@onready var ray_cast_2d = $RayCast2D

# 玩家会在换角色时被销毁重建；池化子弹不得长期缓存旧引用（见 PlayerRef）。
func _ensure_player() -> Node:
	player = PlayerRef.ensure(self, player)
	return player

func _ready():
	player = PlayerRef.resolve(self)
	direction = Vector2.RIGHT.rotated(global_rotation)
	velocity = direction * speed
	ray_cast_2d.target_position.x = speed * 0.0167
	PoolManager.add_pool(pool_id,self)
	manages_own_hits = does_direct_hit()
	if manages_own_hits:
		_setup_self_hits()
	if line != null and line_2 != null:
		var p := _ensure_player()
		line.life_timer = 4
		line_2.life_timer = line.life_timer
		if p != null:
			line.scale_mult = p.stats.bullet_scale
			line_2.scale_mult = p.stats.bullet_scale
		line.update_width()
		line_2.update_width()
	
	is_on_ready()

func is_on_ready():
	is_ready = true
	active_state()

# 是否走直击（自检 HurtBox 结算）。迫击炮弹（PlayerMortarBullet）覆写为 false：
# 不产生直击伤害，只靠落点爆炸（bullet_explosion）。
func does_direct_hit() -> bool:
	return true

func apply_penetrate_dealt():
	var cb: Callable = func(victim: Node, _actual_damage: float):
		var is_prop: bool = victim.is_in_group("SceneProp")
		if not is_prop:
			GameEvents.emit_player_bullet_hit_enemy(self, victim)
			var p := _ensure_player()
			if p != null:
				damage_data.knockback_direction = (victim.global_position - p.global_position).normalized()
		bulletSmoke(global_position)
		penetrate -= victim.stats.penetrate_resis
		if penetrate <= 0:
			if collision_num > 0:
				direction = Vector2.RIGHT.rotated(global_rotation + randf_range(0.7, 1.3) * PI)
				velocity = direction * speed
				collision_num -= 1
			else:
				GameEvents.emit_player_bullet_free_position(self.global_position)
				idle_state()
	damage_data.on_damage_dealt.append(cb)

func idle_state():
	if is_idle == 0:
		ExtensionHooks.notify(ExtensionHooks.on_projectile_despawned, [self])
	is_idle = 1
	set_physics_process(false)
	if GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.disconnect(_on_bullet_kill_timer_timeout)
	_clear_self_hits()
	_request_shape_disabled(true)
	ray_cast_2d.enabled = false
	in_idle.emit(self)
	can_r = false
	homing = false
	_homing_target = null
	_homing_scan_cd = 0
	target_position = Vector2.ZERO
	self.visible = false
	self.global_position = Vector2.ZERO
	self.velocity = Vector2.ZERO
	if line != null and line_2 != null:
		line.is_idle = true
		line_2.is_idle = true
		line.reset()
		line_2.reset()

func active_state():
	
	if is_ready == false:
		return
	
	is_idle = 0
	set_physics_process(true)
	acceleration = Vector2.ZERO
	_clear_self_hits()
	if !GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.connect(_on_bullet_kill_timer_timeout)
	_request_shape_disabled(false)
	ray_cast_2d.enabled = true
	direction = Vector2.RIGHT.rotated(global_rotation)
	self.velocity = direction * speed
	ray_cast_2d.target_position.x = speed * 0.0167
	if slow_down == true:
		ACCELERATION = speed / slow_time
	if line != null and line_2 != null:
		var p := _ensure_player()
		line.reset()
		line_2.reset()
		line.is_idle = false
		line_2.is_idle = false
		line.life_timer = 4
		line_2.life_timer = line.life_timer
		if p != null:
			line.scale_mult = p.stats.bullet_scale
			line_2.scale_mult = p.stats.bullet_scale
		line.update_width()
		line_2.update_width()
	self.visible = true
	flight_time = 0
	# 朝向一次定型；之后仅在变向（r_move/反弹）时更新，直线弹不再每帧重算
	rotation = direction.angle()

func _physics_process(delta):
	
	if is_idle == 1:
		return
	
	_tick_self_hits(delta)
	
	if slow_down == true:
		var v_value = move_toward(velocity.length(), 0, ACCELERATION * delta)
		velocity = direction * v_value
	
	if ray_cast_2d.is_colliding():
		var collider = ray_cast_2d.get_collider()
		if collider.is_in_group("BulletWall"):
			var collision_position: Vector2 = ray_cast_2d.get_collision_point()
			global_position = collision_position
			if collision_num > 0:
				collision_num -= 1
				velocity = IsoProjection.bounce(velocity, ray_cast_2d.get_collision_normal())
				rotation = velocity.angle()
				GameEvents.emit_player_bullet_collision(self)
			
			else:
				bulletSmoke(collision_position)
				GameEvents.emit_player_bullet_free_position(self.global_position)
				idle_state()
	
	if homing:
		_refresh_homing_target()
		if _homing_target != null and global_position.distance_to(_homing_target.global_position) <= homing_range:
			target_position = _homing_target.global_position
			r_move(delta)
	elif can_r == true:
		r_move(delta)
	
	global_position += velocity * delta
	flight_time += delta

func _refresh_homing_target() -> void:
	if _homing_target != null and is_instance_valid(_homing_target) and _homing_scan_cd > 0:
		_homing_scan_cd -= 1
		return
	_homing_target = Targeting.nearest_enemy(global_position)
	_homing_scan_cd = homing_scan_interval

func r_move(delta: float):
	# 保持 direction 为单位朝向：否则 slow_down 的 velocity = direction * v_value 会指数放大
	direction = (target_position - self.global_position).normalized()
	acceleration += (direction * speed - velocity).normalized() * r_speed
	velocity += acceleration * delta
	velocity = velocity.limit_length(speed)
	if velocity != Vector2.ZERO:
		rotation = velocity.angle()

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

func smoke_add():
	var ins = PoolManager.get_pool("bullet_smoke_1")
	if ins == null or ins.is_idle == 0:
		ins = bullet_smoke.instantiate()
		get_tree().get_first_node_in_group("BulletRoot").add_child(ins)
	
	return ins

func _on_bullet_kill_timer_timeout():
	if is_idle == 1:
		return
	
	if kill_time > 0:
		kill_time -= 1
	else:
		bulletSmoke(global_position)
		GameEvents.emit_player_bullet_free_position(self.global_position)
		idle_state()

func bulletSmoke(smoke_position: Vector2):
	var ins = smoke_add()
	ins.global_position = smoke_position
	ins.rotation = rotation + PI
	ins.smoke_anim()
