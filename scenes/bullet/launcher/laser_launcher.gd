extends Node2D

@export var pool_id: String
@export var laser_quantity: int = 4
@export_range(0, 360) var laser_arc :float = 270
@export var laser_bullet: PackedScene


@onready var laser: Node2D = $laser

var laser_group: Array[Node]

var bullet_damage: float = 1
var bullet_knockback: int = 1
var bullet_damage_mult: float = 1

var source_faction: int = Faction.ENEMY_SIDE

# 旋转控制变量
var is_rotating: bool = false
var current_rotation_speed: float = 0.0       # 当前实际速度
var target_rotation_speed: float = 0.0        # 目标速度（0 = 停止）
var speed_transition_time: float = 0.5        # 速度过渡时间（秒）
var speed_transition_timer: float = 0.0
var initial_speed: float = 0.0        # 过渡开始时的速度

# 配置参数
@export var max_rotation_speed: float = 50.0     # 最大速度（度/秒）
@export var acceleration_curve: float = 2.0       # 加速曲线强度（1=线性，>1=先慢后快）
const WARNING_TICKS: int = 15           #预警时间(0.1秒)
const END_TICKS: int = 15               #收尾淡出时间(0.1秒)
@export var life_time: int = 100                 #出光持续时间(0.1秒)，不含预警；每次开火重置
var life_time_left: int = 0
var warning_time: int = 0               #预警时间(0.1秒)
var end_time: int = 0

var is_idle: int = 1
var is_stop: bool = false

func _ready() -> void:
	PoolManager.add_pool(pool_id,self)
	creat_laser()

func idle_state():
	if is_idle == 0:
		ExtensionHooks.notify(ExtensionHooks.on_projectile_despawned, [self])
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	self.visible = false
	is_rotating = false
	is_stop = false
	#self.global_position = Vector2.ZERO
	#clear_laser()

func active_state():
	is_idle = 0
	life_time_left = life_time
	warning_time = 0
	end_time = 0
	is_stop = false
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	self.visible = true
	sync_laser_stats()
	laser_shoot()
	ProjectileSpawner.notify_local(self, get_parent(), source_faction)

func sync_laser_stats():
	for i in laser_group:
		if i == null or not is_instance_valid(i):
			continue
		i.bullet_damage = bullet_damage
		i.bullet_knockback = bullet_knockback
		i.bullet_damage_mult = bullet_damage_mult
		i.source_faction = source_faction

func clear_laser():
	laser_group.clear()
	for i in laser.get_children():
		i.queue_free()

func time_count():
	if warning_time > 0:
		warning_time -= 1
		if warning_time <= 0:
			if life_time_left > 0:
				start_rotating()
			else:
				idle_state()
	elif is_rotating and is_stop == false:
		life_time_left -= 1
		if life_time_left <= 0:
			stop_rotating()
	
	if end_time > 0:
		end_time -= 1
		if end_time <= 0:
			idle_state()

func _physics_process(delta: float) -> void:
	if speed_transition_timer > 0:
	# 正在速度过渡中
		speed_transition_timer -= delta
		var t = 1.0 - (speed_transition_timer / speed_transition_time)
		t = clamp(t, 0.0, 1.0)
		
		# 使用 SmoothStep 实现缓入缓出
		var eased_t = smoothstep(0.0, 1.0, t)
		
		# 插值当前速度
		current_rotation_speed = lerp(initial_speed, target_rotation_speed, eased_t)
	
	# 过渡结束，清理标志
	if speed_transition_timer <= 0:
		current_rotation_speed = target_rotation_speed
	
	# 应用旋转（每秒 rotation 是弧度，需要转换）
	if current_rotation_speed != 0:
	# Godot 的 rotation 使用弧度，角度转弧度：degrees_to_radians()
		rotation += deg_to_rad(current_rotation_speed * delta)

# 开始旋转（平滑启动）
func start_rotating():
	if is_rotating:
	# 如果已经在旋转，只改变目标速度
		change_speed(max_rotation_speed)
	else:
		is_rotating = true
		change_speed(max_rotation_speed)

# 停止旋转（平滑停止）
func stop_rotating():
	if is_rotating and is_stop == false:
		is_stop = true
		laser_end()
		change_speed(0.0)
		end_time = END_TICKS

# 改变旋转速度（带平滑过渡）
func change_speed(new_speed: float):
	if not is_rotating and new_speed == 0:
		return
	
	# 记录当前速度作为起始点
	initial_speed = current_rotation_speed
	target_rotation_speed = new_speed
	speed_transition_timer = speed_transition_time
	
	# 如果目标速度为0且过渡完成，标记停止
	if new_speed == 0:
	# 设置一个延迟检查，在_process中会自然过渡到0
		pass

# 立即停止（无平滑，粗暴停止）
func stop_immediately():
	laser_end()
	current_rotation_speed = 0
	target_rotation_speed = 0
	speed_transition_timer = 0
	is_rotating = false

# 设置最大速度（度/秒）
func set_max_speed(speed_deg_per_sec: float):
	max_rotation_speed = speed_deg_per_sec

# 设置速度过渡时间（秒）
func set_transition_time(time_sec: float):
	speed_transition_time = time_sec

# 获取当前旋转速度（度/秒）
func get_current_speed() -> float:
	return current_rotation_speed

# 检查是否正在旋转
func is_spinning() -> bool:
	return is_rotating and current_rotation_speed != 0

func creat_laser():
	for i in laser_quantity:
		var ins = laser_bullet.instantiate()
		laser.add_child(ins)
		laser_group.append(ins)
		ins.bullet_damage = bullet_damage
		ins.bullet_knockback = bullet_knockback
		ins.bullet_damage_mult = bullet_damage_mult
		ins.source_faction = source_faction
		var arc_rad = deg_to_rad(laser_arc)
		var increment = arc_rad / (laser_quantity - 1)
		ins.global_rotation = (
			Vector2.RIGHT.angle() +
			increment * i -
			arc_rad / 2
		)

func laser_shoot():
	if laser_group != null:
		for i in laser_group:
			i.laser_warning()
		warning_time = WARNING_TICKS

func total_active_ticks() -> int:
	return WARNING_TICKS + life_time + END_TICKS

func laser_end():
	if laser_group != null:
		for i in laser_group:
			i.laser_end()


# 联机（仅表现端）：敌方激光对本地玩家开放伤害洞（只命中玩家层，不命中其它）
func open_network_player_damage_hole() -> void:
	if source_faction == Faction.PLAYER_SIDE:
		return
	for i in laser_group:
		if i != null and is_instance_valid(i) and i.has_method("open_network_player_damage_hole"):
			i.call("open_network_player_damage_hole")
