extends HitBox

var dir: Vector2
var dir2: Vector2
var dir_v: Vector2

var speed:float = 350
const speed_time:int = 1
var accel:float

var is_critical: bool

var enemy_body:Array = []

var equip_damage:int = 1
var equip_knockback:int = 0
var explosion_range:float = 1

var kill_time: int = 110

var cd_time: int = 0

var is_idle: int = 1

var is_ready: bool = false

var target: Vector2 = Vector2.ZERO
var velocity: Vector2

@export var r_speed: int = 80
@export var pool_id: String = "shiro_missile"
var acceleration: Vector2 = Vector2.ZERO

@onready var missile_explosion:PackedScene = preload("res://script/explosion_damage.tscn")
@onready var missile = $Missile
@onready var marker_2d = $%Marker2D
@onready var collision_shape_2d = $TrackBox/CollisionShape2D
@onready var gpu_particles_2d = $Missile/Marker2D/GPUParticles2D

func _ready():
	dir_v = Vector2.RIGHT.rotated(global_rotation)
	set_deferred("rotation", 0)
	velocity = dir_v * speed
	PoolManager.add_pool(pool_id,self)
	is_on_ready()
	area_entered.connect(_on_hit_box_area_entered)

func is_on_ready():
	is_ready = true
	active_state()

func idle_state():
	if is_idle == 0:
		ExtensionHooks.notify(ExtensionHooks.on_projectile_despawned, [self])
	add_explosion()
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	is_critical = false
	gpu_particles_2d.emitting = false
	enemy_body.clear()
	target = Vector2.ZERO
	self.visible = false
	self.global_position = Vector2.ZERO
	self.velocity = Vector2.ZERO

# 远端纯视觉克隆专用销毁：复位但不生成爆炸（爆炸由拥有者广播，走特效通道，避免重复）
func visual_idle_state():
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	is_critical = false
	gpu_particles_2d.emitting = false
	enemy_body.clear()
	target = Vector2.ZERO
	self.visible = false
	self.global_position = Vector2.ZERO
	self.velocity = Vector2.ZERO

func active_state():
	
	if is_ready == false:
		return
	
	is_idle = 0
	acceleration = Vector2.ZERO
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	dir_v = Vector2.RIGHT.rotated(global_rotation)
	gpu_particles_2d.restart()
	self.velocity = dir_v * speed
	self.visible = true
	set_deferred("rotation", 0)

func time_count():
	if kill_time > 0:
		kill_time -= 1
		if kill_time <= 0:
			add_explosion()
			idle_state.call_deferred()
	
	if cd_time > 0:
		cd_time -= 1
		if cd_time <= 0:
			collision_shape_2d.set_deferred("disabled",false)

func close_shape():
	collision_shape_2d.set_deferred("disabled",true)
	cd_time = 5

func _physics_process(delta):
	
	if is_idle == 1:
		return
	
	if target != Vector2.ZERO:
		dir = (target - self.global_position).normalized()
		dir_v = dir * speed
		acceleration += (dir_v - velocity).normalized() * r_speed
		velocity += acceleration * delta
	velocity = velocity.limit_length(speed)
	
	global_position += velocity * delta
	missile.v = velocity.normalized().angle()

func sort_enemy():
	if enemy_body.size() != 0:
		for i in range(enemy_body.size() - 1, -1, -1):
			if enemy_body[i] == null or not is_instance_valid(enemy_body[i]):
				enemy_body.remove_at(i)
		enemy_body.sort_custom(
			func(x, y):
				return x.global_position.distance_to(self.global_position) < y.global_position.distance_to(self.global_position)
		)

func _on_hit_box_area_entered(hurt_box: Area2D):
	
	if is_idle == 1:
		return
	
	if hurt_box is HurtBox:
		idle_state.call_deferred()

func add_explosion():
	ProjectileSpawner.spawn_core(
		missile_explosion, "player_explosion", "BulletRoot", self, Faction.PLAYER_SIDE,
		marker_2d.global_position, 0.0, Vector2.ZERO,
		false, true, true,
		Callable(self, "_configure_explosion"),
		Callable(),
		Callable(self, "_post_explosion")
	)

func _configure_explosion(node: Node) -> void:
	node.damage_data = damage_data.duplicate(true)
	node.explosion_range = explosion_range

func _post_explosion(node: Node) -> void:
	node.is_explosion()

func _on_track_box_body_entered(body):
	if body.is_in_group("Enemy"):
		enemy_body.append(body)
	sort_enemy()
	if not enemy_body.is_empty() and is_instance_valid(enemy_body[0]):
		target = enemy_body[0].global_position
	close_shape()

func _on_track_box_body_exited(body):
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Enemy")  and enemy_body.has(body):
		enemy_body.remove_at(enemy_body.find(body))
	sort_enemy()
