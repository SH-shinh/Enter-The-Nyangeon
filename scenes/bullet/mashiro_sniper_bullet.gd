extends RayCast2D

signal enemy_body_get(body: Node)
signal in_idle

@export var pool_id: String = "player_bullet"
@export var can_r: bool = false
@export var r_speed: int = 50
var acceleration: Vector2 = Vector2.ZERO

@onready var bullet_smoke: PackedScene = preload("res://scenes/bullet/bullet_smoke.tscn")
@onready var collision_shape_2d = $HitBox/CollisionShape2D
@onready var line_2d: Line2D = $Line2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var hit_box = $HitBox

var damage_data: DamageData

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

var flight_time: float = 0.0

var cd_time:int = 0

var player: Node

var get_end: bool = false

var _shape_gen: int = 0

# 统一形状启停出口：自增代数并延迟写入，作废同帧残留的旧延迟调用，
# 避免在物理 query flush 期直接写 Area2D 形状（area_set_shape_disabled 报错）。
func _request_shape_disabled(value: bool) -> void:
	_shape_gen += 1
	call_deferred("_set_shape_disabled_guarded", value, _shape_gen)

func _set_shape_disabled_guarded(value: bool, gen: int) -> void:
	if gen != _shape_gen:
		return
	collision_shape_2d.disabled = value

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	PoolManager.add_pool(pool_id,self)
	hit_box.area_entered.connect(_on_area_entered)
	hit_box.area_exited.connect(_on_area_exited)
	# 场景里的 RectangleShape2D 是共享子资源，多弹道（如 S 字母弹道+2）或多发同时存在时，
	# update_poin 会互相覆盖 size.x。命中框位置按各自 end_point 摆放，长度却被最后一条覆盖，
	# 于是较短光束的命中框会向枪口后方延伸出额外判定。每个实例复制一份专属形状。
	collision_shape_2d.shape = collision_shape_2d.shape.duplicate()
	is_on_ready()

func is_on_ready():
	is_ready = true
	active_state()

func idle_state():
	if is_idle == 0:
		ExtensionHooks.notify(ExtensionHooks.on_projectile_despawned, [self])
	is_idle = 1
	set_physics_process(false)
	get_end = false
	if GameEvents.global_time_count.is_connected(add_damage_data):
		GameEvents.global_time_count.disconnect(add_damage_data)
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	cd_time = 0
	_request_shape_disabled(true)
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
	set_physics_process(true)
	flight_time = 0.0
	get_end = false
	if !GameEvents.global_time_count.is_connected(add_damage_data):
		GameEvents.global_time_count.connect(add_damage_data)
	_request_shape_disabled(false)
	self.enabled = true
	if slow_down == true:
		ACCELERATION = speed / slow_time
	self.visible = true
	self.scale.x = 1

func _physics_process(delta: float) -> void:
	if is_idle == 1:
		return
	flight_time += delta
	update_poin(get_bullet_position())

func apply_penetrate_dealt():
	damage_data.on_damage_dealt.append(func(victim: Node, _actual_damage: float):
		if victim == null or not is_instance_valid(victim):
			return
		if player == null or not is_instance_valid(player):
			return
		damage_data.knockback_direction = (victim.global_position - player.global_position).normalized()
	)

func smoke_add():
	
	var ins = PoolManager.get_pool("bullet_smoke_1")
	if ins == null or ins.is_idle == 0:
		ins = bullet_smoke.instantiate()
		get_parent().add_child(ins)
	
	return ins

func update_poin(end_point: Vector2):
	if get_end == false and is_ready == true:
		scale.x = 1
		get_end = true
		line_2d.set_point_position(1, end_point)
		
		collision_shape_2d.shape.size.x = end_point.x
		collision_shape_2d.position.x = end_point.x / 2
		
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
		var collision_direction = IsoProjection.bounce(bullet_direction, normal)
		return collision_direction.normalized()
	return Vector2.ZERO

func add_collision_bullet(_end_point: Vector2):
	if collision_num > 0:
		collision_num -= 1
		GameEvents.emit_player_bullet_collision(self)
		var now_bullet = PoolManager.get_pool(pool_id)
		if now_bullet == null or now_bullet.is_idle == 0:
			now_bullet = self.duplicate()
			get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
		
		var direction: Vector2 = get_bullet_collision()
		now_bullet.damage_data = damage_data.duplicate(true)
		now_bullet.speed = speed
		now_bullet.penetrate = penetrate
		now_bullet.collision_num = collision_num
		now_bullet.global_position = get_collision_point()
		now_bullet.kill_time = kill_time
		now_bullet.global_rotation = direction.angle()
		now_bullet.scale = self.scale
		now_bullet.active_state()
		ProjectileSpawner.notify_local(now_bullet, self, Faction.PLAYER_SIDE)

func count_bullet_speed():
	hit_box.damage_data = damage_data
	animation_player.speed_scale = clamp(0.1, 0.001 * speed, 1)
	animation_player.play("shoot")

func _on_area_2d_body_entered(body):
	if is_idle == 1:
		return
	
	if body.is_in_group("Enemy"):
		enemy_group.push_back(body)

func time_count():
	if is_idle == 1:
		return
	if cd_time > 0:
		cd_time -= 1
		if cd_time <= 0:
			add_damage_data()

func close_shape():
	_request_shape_disabled(true)
	cd_time = 1
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)

func add_damage_data():
	hit_box.damage_data = damage_data
	if !enemy_group.is_empty():
		for i in enemy_group:
			if i == null or not is_instance_valid(i):
				continue
			i.hit_received.emit(hit_box.damage_data)

func _on_area_entered(hurtbox: Area2D):
	if is_idle == 1:
		return
	if hurtbox == null or not is_instance_valid(hurtbox):
		return
	
	if hurtbox is HurtBox and !enemy_group.has(hurtbox):
		enemy_group.push_back(hurtbox)

func _on_area_exited(hurtbox: Area2D):
	if hurtbox == null or not is_instance_valid(hurtbox):
		return
	if hurtbox is HurtBox and enemy_group.has(hurtbox):
		enemy_group.remove_at(enemy_group.find(hurtbox))


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "shoot":
		idle_state()
