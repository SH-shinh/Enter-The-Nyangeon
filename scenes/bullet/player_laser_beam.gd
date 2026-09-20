extends RayCast2D


signal in_idle


@export var pool_id: String = "player_laser_beam"
@export var tick_damage_mult: float = 0.4
@export var damage_tick_interval: int = 1
@export var segment_count: int = 10
@export var lag_speed: float = 7.0
@export var tip_lag_mult: float = 3.0
@export var lag_start: float = 0.5
@export var max_length: float = 1800.0
@export var color_cycle_speed: float = 0.4
@export var base_hue: float = 0.58
@export var hue_range: float = 0.06
@export var base_width: float = 26.0
@export var width_jitter: float = 3.0
@export var width_wobble_freq: float = 30.0
@export var grow_time: float = 0.15
@export var hit_box_width: float = 26.0


const LASER_SHADER := preload("res://shaders/laser_beam.gdshader")


@onready var line_2d: Line2D = $Line2D
@onready var line_2d_2: Line2D = $Line2D2
@onready var impact_particles: GPUParticles2D = $ImpactParticles
@onready var impact_particles_2: GPUParticles2D = $ImpactParticles2
@onready var animation_player: AnimationPlayer = $AnimationPlayer


var damage_data: DamageData
var is_idle: int = 1
var damage_cd: int = 0
var _time: float = 0.0
var _angles: PackedFloat32Array
var _just_activated: bool = false
var grow: float = 0.0
var player: Node

# 每段一个 HitBox，贴合 Line2D；point_targets[i] 为第 i 段锁定的敌人（留作追踪接口）
var _segments: Array[Area2D] = []
var _seg_shapes: Array[CollisionShape2D] = []
var point_targets: Array[Node] = []


func _ready() -> void:
	PoolManager.add_pool(pool_id, self)
	GameEvents.global_time_count.connect(_time_count)
	_angles = PackedFloat32Array()
	_angles.resize(segment_count)
	var mat := ShaderMaterial.new()
	mat.shader = LASER_SHADER
	line_2d.material = mat
	line_2d_2.material = mat
	player = get_tree().get_first_node_in_group("Player")
	animation_player.animation_finished.connect(_on_animation_finished)
	_build_segments()


func _build_segments() -> void:
	point_targets.resize(segment_count)
	for i in range(segment_count):
		var area := Area2D.new()
		area.collision_layer = 32768
		area.collision_mask = 16384
		area.monitorable = false
		area.monitoring = false
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(1.0, hit_box_width)
		shape.shape = rect
		area.add_child(shape)
		add_child(area)
		_segments.append(area)
		_seg_shapes.append(shape)


func follow(muzzle_global: Vector2, aim_angle: float, delta: float) -> void:
	global_position = muzzle_global
	if _just_activated:
		for i in range(segment_count):
			_angles[i] = aim_angle
		_just_activated = false
	else:
		var weight := 1.0 - exp(-lag_speed * delta)
		_angles[0] = aim_angle
		var start_seg := clampi(int(round(lag_start * float(segment_count))), 1, segment_count - 1)
		var lag_count := segment_count - 1 - start_seg
		for i in range(1, segment_count):
			if i < start_seg or lag_count <= 0:
				_angles[i] = _angles[i - 1]
			else:
				var t := float(i - start_seg) / float(lag_count)
				var seg_weight: float = weight / lerp(1.0, tip_lag_mult, t)
				_angles[i] = lerp_angle(_angles[i], _angles[i - 1], seg_weight)
	global_rotation = _angles[0]


func active_state() -> void:
	is_idle = 0
	enabled = true
	visible = true
	damage_cd = 0
	_just_activated = true
	impact_particles.emitting = true
	impact_particles_2.emitting = true
	grow = 0.0
	animation_player.play("grow")
	_set_segments_active(true)
	update_beam()
	self.scale.x = 1.0


func idle_state() -> void:
	is_idle = 1
	enabled = false
	damage_cd = 0
	impact_particles.emitting = false
	impact_particles_2.emitting = false
	animation_player.play_backwards("grow")
	_set_segments_active(false)
	in_idle.emit()


func _set_segments_active(active: bool) -> void:
	for area in _segments:
		area.monitoring = active


func _on_animation_finished(_anim_name: StringName) -> void:
	if is_idle == 1:
		visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	var hue := base_hue + sin(_time * color_cycle_speed) * hue_range
	line_2d.default_color = Color.from_hsv(hue, 1.0, 10.0, 1.0)
	line_2d_2.default_color = Color.from_hsv(hue, 0.25, 10.0, 1.0)
	var w := (base_width + sin(_time * width_wobble_freq) * width_jitter) * grow
	line_2d.width = w
	line_2d_2.width = max(2.0, w * 0.35)


func _physics_process(_delta: float) -> void:
	if is_idle == 1:
		return
	update_beam()


func update_beam() -> void:
	var length := get_beam_length()
	var seg := length / float(segment_count)
	var pts := PackedVector2Array()
	var p := Vector2.ZERO
	pts.append(p)
	var base := _angles[0]
	for i in range(segment_count):
		var local_angle := _angles[i] - base
		var target := _valid_target(i)
		if target != null and i > 0:
			var point_global := global_position + p.rotated(global_rotation)
			local_angle = (target.global_position - point_global).angle() - global_rotation
		p += Vector2(seg, 0).rotated(local_angle)
		pts.append(p)
	line_2d.points = pts
	line_2d_2.points = pts
	impact_particles.position = Vector2(length, 0)
	impact_particles_2.position = Vector2(length, 0)
	_update_segments(pts)


func _update_segments(pts: PackedVector2Array) -> void:
	for i in range(_segments.size()):
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var area := _segments[i]
		area.position = (a + b) * 0.5
		area.rotation = d.angle()
		(_seg_shapes[i].shape as RectangleShape2D).size = Vector2(max(d.length(), 1.0), hit_box_width)


func get_beam_length() -> float:
	if is_colliding():
		return max((get_collision_point() - global_position).length(), 1.0)
	return max_length


func _time_count() -> void:
	if is_idle == 1:
		return
	if damage_cd > 0:
		damage_cd -= 1
		return
	_apply_damage()


func _apply_damage() -> void:
	if damage_data == null:
		return
	var hit: Dictionary = {}
	for area in _segments:
		if not area.monitoring:
			continue
		for other in area.get_overlapping_areas():
			if other is HurtBox:
				hit[other] = true
	for hurtbox in hit.keys():
		if hurtbox == null or not is_instance_valid(hurtbox):
			continue
		hurtbox.hit_received.emit(damage_data)
	damage_cd = damage_tick_interval


func _valid_target(i: int) -> Node:
	if i >= 0 and i < point_targets.size():
		var t := point_targets[i]
		if t != null and is_instance_valid(t):
			return t
	return null


func get_segment_count() -> int:
	return segment_count


func set_point_target(index: int, enemy: Node) -> void:
	if index < 0 or index >= point_targets.size():
		return
	point_targets[index] = enemy


func clear_point_targets() -> void:
	for i in range(point_targets.size()):
		point_targets[i] = null
