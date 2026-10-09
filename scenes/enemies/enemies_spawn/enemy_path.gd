extends Node2D

@export var enemy_body: Node
@export var path_speed: float = 0.08
@export var min_scale: float = 0.1
@export var follow_range: float = 80.0
@export var half_extents: Vector2 = Vector2(744, 368)
@export var center: Vector2 = Vector2(704, 448)
@export var rings: int = 4

var progress: float = 0.0
var lap: float = 0.0

func _ready() -> void:
	_apply_position()
	set_physics_process(false)

func idle_state() -> void:
	progress = 0.0
	lap = 0.0
	set_physics_process(false)
	if enemy_body != null and is_instance_valid(enemy_body):
		enemy_body.route_target = null

func active_state() -> void:
	lap = 0.0
	_apply_position()
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if enemy_body == null or not is_instance_valid(enemy_body):
		return
	var dist: float = enemy_body.global_position.distance_to(global_position)
	var k: float = clamp(1.0 - dist / follow_range, 0.3, 1.0)
	var step: float = path_speed * delta * k
	progress = wrapf(progress + step, 0.0, 1.0)
	lap += step
	_apply_position()

func _depth_factor() -> float:
	var ring_count: int = max(1, rings)
	var period: float = float(ring_count) * 2.0
	var phase: float = fmod(lap, period)
	var rf: float
	if phase <= float(ring_count):
		rf = phase
	else:
		rf = period - phase
	return lerp(1.0, min_scale, rf / float(ring_count))

func _apply_position() -> void:
	global_position = center + _sample_border(progress) * _depth_factor()

func _build_vertices() -> Array[Vector2]:
	return [
		Vector2(0, -half_extents.y),
		Vector2(half_extents.x, 0),
		Vector2(0, half_extents.y),
		Vector2(-half_extents.x, 0),
	]

func _sample_from(verts: Array[Vector2], t: float) -> Vector2:
	var seg: float = t * float(verts.size())
	var i: int = int(seg) % verts.size()
	var s: float = seg - floor(seg)
	return verts[i].lerp(verts[(i + 1) % verts.size()], s)

func _sample_border(t: float) -> Vector2:
	return _sample_from(_build_vertices(), t)

func _corner_index(t: float) -> int:
	return clampi(int(floor(t * 4.0)), 0, 3)

func get_spawn_point(t: float) -> Vector2:
	return center + _build_vertices()[_corner_index(t)]

func set_start_progress(value: float) -> void:
	progress = float(_corner_index(value)) / 4.0
	lap = 0.0
	_apply_position()

func set_body_target() -> void:
	if enemy_body != null:
		# 保留 player 改写以兼容旧读取（如 sweeper 蓄力距离）；route_target 为独立权威存储。
		enemy_body.player = self
		enemy_body.route_target = self
		if enemy_body.stats != null and not enemy_body.stats.is_dead.is_connected(idle_state):
			enemy_body.stats.is_dead.connect(idle_state)
