extends RayCast2D

signal enemy_body_get(body: Node)
signal in_idle

@export var pool_id: String = "player_bullet"
@export var can_r: bool = false
@export var r_speed: int = 50
var acceleration: Vector2 = Vector2.ZERO

@onready var bullet_smoke: PackedScene = preload("res://scenes/bullet/bullet_smoke.tscn")
@onready var area_2d = $Area2D
@onready var collision_shape_2d = $Area2D/CollisionShape2D
@onready var line_2d: Line2D = $Line2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var is_ready: bool = false
var ACCELERATION: float
var penetrate: int = 1 #穿透值
var speed: int = 300
var collision_num: int = 0 #反弹次数
var bullet_damage: int = 0
var bullet_knockback: int = 0
var kill_time: int = 110
var append_damage: int = 0 #追加伤害
var is_critical: bool = false
var enemy_group: Array[Node]
@export var is_player_shoot: bool = false
@export var slow_down: bool = false
@export var slow_time: float = 0

var is_idle: int = 1

var cd_time:int = 0

var player: Node

var get_end: bool = false

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	PoolManager.add_pool(pool_id,self)
	
	is_on_ready()

func is_on_ready():
	is_ready = true
	active_state()

func idle_state():
	is_idle = 1
	get_end = false
	if GameEvents.global_time_count.is_connected(add_damage):
		GameEvents.global_time_count.disconnect(add_damage)
	collision_shape_2d.disabled = true
	self.enabled = false
	in_idle.emit()
	is_critical = false
	is_player_shoot = false
	can_r = false
	self.visible = false
	self.global_position = Vector2.ZERO
	if !enemy_group.is_empty():
		enemy_group.clear()

func active_state():
	
	if is_ready == false:
		return
	
	is_idle = 0
	get_end = false
	if !GameEvents.global_time_count.is_connected(add_damage):
		GameEvents.global_time_count.connect(add_damage)
	collision_shape_2d.disabled = false
	self.enabled = true
	if slow_down == true:
		ACCELERATION = speed / slow_time
	self.visible = true
	self.scale.x = 1

func _physics_process(delta: float) -> void:
	if is_idle == 1:
		return
	
	update_poin(get_bullet_position())

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

func update_poin(end_point: Vector2):
	if get_end == false and is_ready == true:
		get_end = true
		line_2d.points[1] = end_point
		count_bullet_speed()
		add_collision_bullet(end_point)

func get_bullet_position():
	if is_colliding():
		var l = (get_collision_point() - global_position).length()
		return Vector2(l, 0)
	return Vector2.ZERO

func get_bullet_collision():
	if is_colliding():
		var normal = get_collision_normal()
		var bullet_direction = (get_collision_point() - global_position).normalized()
		var collision_direction = bullet_direction.bounce(normal)
		return collision_direction.normalized()
	return Vector2.ZERO

func add_collision_bullet(end_point: Vector2):
	if collision_num > 0:
		collision_num -= 1
		GameEvents.emit_player_bullet_collision(self)
		var now_bullet = PoolManager.get_pool(pool_id)
		var add_bullet: bool = false
		if now_bullet == null or now_bullet.is_idle == 0:
			now_bullet = self.duplicate()
			get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
		
		var direction: Vector2 = get_bullet_collision()
		now_bullet.speed = speed
		now_bullet.penetrate = penetrate
		now_bullet.collision_num = collision_num
		now_bullet.global_position = get_collision_point()
		now_bullet.kill_time = kill_time
		now_bullet.is_player_shoot = is_player_shoot
		now_bullet.global_rotation = direction.angle()
		now_bullet.is_critical = is_critical
		now_bullet.bullet_damage = bullet_damage
		now_bullet.bullet_knockback = bullet_knockback
		now_bullet.scale = self.scale
		now_bullet.active_state()

func count_bullet_speed():
	animation_player.speed_scale = clamp(0.1, 0.001 * speed, 1)
	animation_player.play("shoot")

func _on_area_2d_body_entered(body):
	if is_idle == 1:
		return
	
	if body.is_in_group("Enemy"):
		enemy_group.push_back(body)

func time_count():
	if cd_time > 0:
		cd_time -= 1
		if cd_time <= 0:
			add_damage()

func add_damage():
	if !enemy_group.is_empty():
		GameEvents.emit_explosion_quantity(enemy_group.size(), self)
		for i in enemy_group.size():
			if enemy_group[i] == null:
				return
			var hit_direction = (enemy_group[i].position - player.position).normalized()
			enemy_group[i].hurt_damage = bullet_damage
			enemy_group[i].hurt_knockback = bullet_knockback
			enemy_group[i].hurt_direction = hit_direction
			
			GameEvents.emit_enemy_body(enemy_group[i],self)
			if is_player_shoot == true:
				GameEvents.emit_player_bullet_hit_enemy(self)
				if is_critical == true:
					GameEvents.emit_player_critical_hit_enemy(enemy_group[i])
					enemy_group[i].is_critical_hit = true
			
			if enemy_group[i].stats.hp <= bullet_damage:
				GameEvents.emit_player_bullet_kill_enemy(self)
			
			var ins = smoke_add()
			ins.global_position = enemy_group[i].global_position
			ins.rotation = hit_direction.angle() + PI
			ins.smoke_anim()
			
			enemy_group[i].emit_signal("is_hurt")
		cd_time = 1
			

func close_shape():
	collision_shape_2d.set_deferred("disabled",true)
	cd_time = 1
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)


func _on_area_2d_body_exited(body: Node2D) -> void:
	if is_idle == 1:
		return
	
	if body.is_in_group("Enemy") and !enemy_group.has(body):
		enemy_group.push_back(body)


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "shoot":
		idle_state()
