class_name Rope
extends Line2D

@export var segment_count : int = 20          # 绳段数量（点数量 = segment_count + 1）
@export var segment_length : float = 5.0      # 每段长度
@export var gravity : Vector2 = Vector2(0, 980)  # 重力加速度
@export var damping : float = 0.99            # 速度衰减（0~1）
@export var constraint_iterations : int = 10  # 约束迭代次数，越多越硬

var rope_points : Array[Vector2] = []         # 当前点位置（本地坐标）
var prev_points : Array[Vector2] = []         # 上一帧点位置（用于 Verlet）
@export var pinned : bool = true              # 是否固定第一个点
var pin_point : Vector2                       # 固定点的本地坐标（如果 pinned）
var target_pos : Vector2                      # 每帧设置：末端的本地坐标

func _ready():
	_init_rope()

func _init_rope():
	rope_points.clear()
	points.clear()
	for i in range(segment_count + 1):
		rope_points.append(Vector2(i * segment_length, 0))
		prev_points.append(rope_points[i])
	points = rope_points

func _physics_process(delta):
	if rope_points.is_empty():
		return
	
	# 1. 更新每个点的位置（Verlet 积分）
	for i in range(rope_points.size()):
		if pinned and i == 0:
			rope_points[i] = pin_point          # 固定端点
			prev_points[i] = pin_point
			continue
		
		var velocity = (rope_points[i] - prev_points[i]) * damping
		var new_pos = rope_points[i] + velocity + gravity * delta * delta
		prev_points[i] = rope_points[i]
		rope_points[i] = new_pos
	
	rope_points[-1] = target_pos
	prev_points[-1] = target_pos
	
	# 2. 多次迭代距离约束，使绳段保持长度
	for _iter in range(constraint_iterations):
		for i in range(rope_points.size() - 1):
			var p1 = rope_points[i]
			var p2 = rope_points[i + 1]
			var delta_pos = p2 - p1
			var dist = delta_pos.length()
			if dist == 0: continue
			var error = (dist - segment_length) / dist
			if pinned and i == 0:
				rope_points[i + 1] -= delta_pos * error
			else:
				rope_points[i] += delta_pos * error * 0.5
				rope_points[i + 1] -= delta_pos * error * 0.5
	
	# 3. 更新 Line2D
	points = rope_points

func set_pinned(pos: Vector2):
	pinned = true
	pin_point = pos
