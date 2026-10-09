class_name EnemyBullet
extends HitBox

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
var velocity: Vector2

var ACCELERATION: float

var is_idle: int = 1
var is_ready: bool = false

var _shape_gen: int = 0

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
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	PoolManager.add_pool(pool_id,self)
	is_on_ready()

# 墙壁判定改走 HitBox(Area2D)：碰撞层含 bullet_wall(2)，与墙/可挡子弹道具重叠即消失
func _on_body_entered(body: Node) -> void:
	if is_idle == 1:
		return
	if body == null or not body.is_in_group("BulletWall"):
		return
	bulletSmoke(global_position)
	idle_state()

func is_on_ready():
	is_ready = true
	active_state()

# 统一形状启停出口：自增代数并延迟写入，作废同帧残留的旧延迟调用，
# 避免在物理 query flush 期直接写 Area2D 形状（area_set_shape_disabled 报错）。
func _request_shape_disabled(value: bool) -> void:
	_shape_gen += 1
	call_deferred("_set_shape_disabled_guarded", value, _shape_gen)

func _set_shape_disabled_guarded(value: bool, gen: int) -> void:
	if gen != _shape_gen:
		return
	collision_shape_2d.disabled = value

func idle_state():
	if is_idle == 0:
		ExtensionHooks.notify(ExtensionHooks.on_projectile_despawned, [self])
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
	_request_shape_disabled(true)
	bullet_idle.emit(self)

func active_state():
	
	if is_ready == false:
		return
	
	is_idle = 0
	if !GameEvents.global_time_count.is_connected(_on_bullet_kill_timer_timeout):
		GameEvents.global_time_count.connect(_on_bullet_kill_timer_timeout)
	
	direction = Vector2.RIGHT.rotated(global_rotation)
	if penetrate < 1:
		penetrate = 1
	now_penetrate = penetrate
	if damage_data != null and not damage_data.on_damage_dealt.has(_on_penetrate_dealt):
		damage_data.on_damage_dealt.append(_on_penetrate_dealt)
	if decay_time != 0:
		if !GameEvents.global_time_count.is_connected(_on_bullet_decay_timer_timeout):
			GameEvents.global_time_count.connect(_on_bullet_decay_timer_timeout)
		ACCELERATION = speed / maxf((kill_time - decay_time) / 10.0, 0.1)
	self.velocity = direction * speed
	self.visible = true
	_request_shape_disabled(false)
	if source_faction == Faction.PLAYER_SIDE:
		collision_layer = 131072
	else:
		collision_layer = 128

func bulletSmoke(smoke_position: Vector2):
	var ins = PoolManager.get_pool("bullet_smoke_2")
	if ins == null or ins.is_idle == 0:
		ins = smoke.instantiate()
		get_parent().add_child(ins)
	
	ins.global_position = smoke_position
	ins.scale = self.scale
	ins.smoke_anim()

func is_stop_false():
	is_stop = false

func _physics_process(delta):
	
	if is_idle == 1:
		return
	
	if is_stop == true:
		return
	
	if is_decay == true:
		var v_value = move_toward(velocity.length(), 0, ACCELERATION * delta)
		velocity = direction * v_value
	
	global_position += velocity * delta

func bullet_clear():
	bulletSmoke(global_position)
	idle_state()

func _on_penetrate_dealt(_victim: Node, _actual_damage: float):
	now_penetrate -= 1

func bullet_kill():
	if now_penetrate <= 0:
		bullet_clear()

func _on_bullet_kill_timer_timeout():
	
	if is_idle == 1:
		return
	
	if kill_time > 0:
		kill_time -= 1
	else:
		bulletSmoke(global_position)
		idle_state()

func _on_bullet_decay_timer_timeout():
	
	if is_idle == 1:
		return
	
	if decay_time > 0:
		decay_time -= 1
	else:
		is_decay = true
