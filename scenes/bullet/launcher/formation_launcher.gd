extends Node2D

class_name FormationController

# 阵型配置
@export var formation_type: String = "hollow_rectangle"
@export var bullet_speed: float = 1.0
@export var rotation_speed: float = 0.0  # 整体旋转速度
@export var bullet_count: int = 12
@export var formation_scale: float = 1.0  # 形状缩放
var center_position: Vector2 = Vector2.ZERO

# 子弹相关
@export var bullet_id: String
@export var bullet_scene: PackedScene
@export var bullet_scale: float = 1
@export var bullet_damage: float
@export var bullet_penetrate: int
@export var collision_num: int
@export var decay_time: float
@export var decay_speed: int
@export var kill_time: float
@export var explosion_range: float
@export var shoot_bullet_num: int
var bullets: Array[Node] = []
var target_positions: Array[Vector2] = []  # 相对位置目标
var bullet_damage_mult: float = 1

# 状态
var is_active: bool = false
var erase_num: int = 0
var velocity: Vector2 = Vector2.ZERO

func setup_formation():
	match formation_type:
		"square":
			setup_square_formation()
		"triangle":
			setup_triangle_formation()
		"circle":
			setup_circle_formation()
		"hollow_square":
			setup_hollow_square_formation()
		"hollow_rectangle":
			setup_hollow_rectangle()

func setup_square_formation():
	# 正方形阵型：4x3的网格
	target_positions.clear()
	var side_length = 20.0 * formation_scale
	var rows = 3
	var cols = 4
	
	for row in range(rows):
		for col in range(cols):
			var x = (col - (cols-1)/2.0) * side_length
			var y = (row - (rows-1)/2.0) * side_length
			target_positions.append(Vector2(x, y))

func setup_triangle_formation():
	# 三角形阵型
	target_positions.clear()
	var size = 15.0 * formation_scale
	var rows = 4
	
	for row in range(rows):
		for col in range(row + 1):
			var x = (col - row/2.0) * size
			var y = row * size
			target_positions.append(Vector2(x, y))

func setup_circle_formation():
	target_positions.clear()
	var radius = 30.0 * formation_scale
	
	for i in range(bullet_count):
		var angle = 2 * PI * i / bullet_count
		var x = cos(angle) * radius
		var y = sin(angle) * radius
		target_positions.append(Vector2(x, y))

func setup_hollow_rectangle(width: float = 45.0, height: float = 55.0, horizontal_bullets: int = 4, vertical_bullets: int = 5):
	"""
	参数化空心长方形
	width: 宽度
	height: 高度
	horizontal_bullets: 水平边的子弹数量
	vertical_bullets: 垂直边的子弹数量
	"""
	target_positions.clear()
	var half_width = width * formation_scale / 2.0
	var half_height = height * formation_scale / 2.0
	
	# 计算间距
	var horizontal_spacing = width * formation_scale / (horizontal_bullets - 1)
	var vertical_spacing = height * formation_scale / (vertical_bullets - 1)
	
	# 上边（从左到右）
	for i in range(horizontal_bullets):
		var x = -half_width + i * horizontal_spacing
		var y = -half_height
		target_positions.append(Vector2(x, y))
	
	# 右边（从上到下，跳过右上角）
	for i in range(1, vertical_bullets):
		var x = half_width
		var y = -half_height + i * vertical_spacing
		target_positions.append(Vector2(x, y))
	
	# 下边（从右到左，跳过右下角）
	for i in range(horizontal_bullets):
		var x = half_width - i * horizontal_spacing
		var y = half_height
		target_positions.append(Vector2(x, y))
	
	# 左边（从下到上，跳过左下角和左上角）
	for i in range(1, vertical_bullets - 1):
		var x = -half_width
		var y = half_height - i * vertical_spacing
		target_positions.append(Vector2(x, y))
	

func setup_hollow_square_formation():
	target_positions.clear()
	var size = 10.0 * formation_scale
	var side_length = 3  # 每边的子弹数量
	var side_width = 8
	var spacing = size / (side_length - 1)
	
	# 上边
	for i in range(side_length):
		var x = -size/2 + i * spacing
		var y = -size/2
		target_positions.append(Vector2(x, y))
	
	# 右边
	for i in range(1, side_width - 1):  # 避免重复角点
		var x = size/2
		var y = -size/2 + i * spacing
		target_positions.append(Vector2(x, y))
	
	# 下边（从右到左）
	for i in range(side_length):
		var x = size/2 - i * spacing
		var y = size/2
		target_positions.append(Vector2(x, y))
	
	# 左边（从下到上，跳过角点）
	for i in range(1, side_width - 1):
		var x = -size/2
		var y = size/2 - i * spacing
		target_positions.append(Vector2(x, y))

func erase_bullet(bullet: Node):
	if bullet.bullet_idle.is_connected(erase_bullet):
		bullet.bullet_idle.disconnect(erase_bullet)
	if bullets.has(bullet):
		var i = bullets.find(bullet)
		bullets[i] = null
		erase_num += 1
	if erase_num >= bullets.size():
		bullets.clear()
		is_active = false

func add_bullet():
	var now_bullet = PoolManager.get_pool(bullet_id)
	var add_bullet: bool = false
	if now_bullet == null or now_bullet.is_idle == 0:
		now_bullet = bullet_scene.instantiate()
		add_bullet = true
	
	now_bullet.scale = Vector2(bullet_scale,bullet_scale)
	now_bullet.bullet_damage =  bullet_damage * bullet_damage_mult
	now_bullet.speed = 0
	now_bullet.penetrate = bullet_penetrate
	now_bullet.collision_num = collision_num
	now_bullet.decay_time = decay_time * 10
	now_bullet.decay_speed = decay_speed
	now_bullet.kill_time = kill_time * 10
	now_bullet.shoot_bullet_num = shoot_bullet_num
	if explosion_range > 0:
		now_bullet.explosion_range = explosion_range
	now_bullet.global_position = global_position
	
	now_bullet.active_state()
	if add_bullet == true:
		get_tree().get_first_node_in_group("BulletRoot").add_child(now_bullet)
	
	return now_bullet

func shoot_bullet():
	if is_active == true:
		return
	erase_num = 0
	setup_formation()
	center_position = Vector2.ZERO
	# 生成新子弹
	set_direction(Vector2.RIGHT.rotated(global_rotation))
	for i in range(target_positions.size()):
		var bullet = add_bullet()
		target_positions[i] = target_positions[i].rotated(global_rotation)
		target_positions[i] += global_position
		bullet.global_position = target_positions[i]
		bullets.append(bullet)
		bullet.bullet_idle.connect(erase_bullet)
	center_position += global_position
	is_active = true

func set_direction(dir: Vector2):
	velocity = dir.normalized() * bullet_speed

func set_rotation_speed(speed: float):
	rotation_speed = speed

func _physics_process(delta):
	if not is_active:
		return
	
	# 整体移动
	if !target_positions.is_empty():
		center_position += velocity * delta
		for i in target_positions.size():
			target_positions[i] += velocity * delta
			
			var bullet = bullets[i]
			if bullet != null:
				bullets[i].global_position = target_positions[i]
	
	# 整体旋转
	if rotation_speed != 0:
		# 更新子弹的相对位置（考虑旋转）
		for i in range(bullets.size()):
			var bullet = bullets[i]
			if bullet != null:
				var rotated_offset = (target_positions[i] - center_position).rotated(rotation_speed * delta)
				target_positions[i] = rotated_offset + center_position
				bullets[i].global_position = target_positions[i]

func destroy():
	is_active = false
	# 可选：阵型破坏时子弹散开
	for bullet in bullets:
		if is_instance_valid(bullet):
			bullet.release_from_formation()
			queue_free()
