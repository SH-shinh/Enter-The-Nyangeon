extends CharacterBody2D

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

func is_on_ready():
	is_ready = true
	active_state()

func idle_state():
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

func active_state():
	
	if is_ready == false:
		return
	
	is_idle = 0
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
	
	move_and_slide()
	
	missile.v = velocity.normalized().angle()

func sort_enemy():
	if enemy_body.size() != 0:
		enemy_body.sort_custom(
			func(x, y):
				return x.global_position.distance_to(self.global_position) < y.global_position.distance_to(self.global_position)
		)

func _on_hit_box_body_entered(body):
	
	if is_idle == 1:
		return
	
	if body.is_in_group("Enemy"):
		
		#add_explosion()
		
		GameEvents.call_deferred("emit_equip_hit_enemy", body, self)
		idle_state.call_deferred()

func add_explosion():
	var ins = PoolManager.get_pool("player_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = missile_explosion.instantiate()
		add_ins = true
	
	ins.global_position = marker_2d.global_position
	ins.explosion_damage = equip_damage
	ins.explosion_knockback = equip_knockback
	ins.explosion_range = explosion_range
	ins.is_critical = is_critical
	ins.is_equip_shoot = true
	
	ins.active_state()
	if add_ins == true:
		get_tree().get_first_node_in_group("BulletRoot").call_deferred("add_child",ins)
	
	ins.is_explosion.call_deferred()

func _on_track_box_body_entered(body):
	if body.is_in_group("Enemy"):
		enemy_body.append(body)
	sort_enemy()
	target = enemy_body[0].global_position
	close_shape()

func _on_track_box_body_exited(body):
	if body.is_in_group("Enemy")  and enemy_body.has(body):
		enemy_body.remove_at(enemy_body.find(body))
	sort_enemy()
