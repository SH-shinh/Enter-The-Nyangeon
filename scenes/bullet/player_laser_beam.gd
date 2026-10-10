extends RayCast2D


signal in_idle


@export var pool_id: String = "player_bullet"
@export var tick_damage_mult: float = 0.4
@export var damage_tick_interval: int = 1
var segment_count: int = 0
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
@export var wall_collision_mask: int = 2
@export var max_tracked_enemies: int = 9
# 联机：远端镜像位置平滑速度（仅在网络驱动下生效，见 _physics_process）
@export var net_pos_lerp_speed: float = 18.0


const LASER_SHADER := preload("res://shaders/laser_beam.gdshader")


@onready var line_2d: Line2D = $Line2D
@onready var line_2d_2: Line2D = $Line2D2
@onready var impact_particles: GPUParticles2D = $ImpactParticles
@onready var impact_particles_2: GPUParticles2D = $ImpactParticles2
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var beam_hit_box: Area2D = $BeamHitBox


var damage_data: DamageData
var is_idle: int = 1
var damage_cd: int = 0
var _time: float = 0.0
var flight_time: float = 0.0
var _angles: PackedFloat32Array
var _just_activated: bool = false
var grow: float = 0.0
var player: Node

# 场景预置 BeamHitBox 下的 CollisionShape2D，逐个贴合 Line2D 折线段。
# 结算以「即时形状查询」为准，不维护 area_entered/exited 集合：
# 边沿事件在 monitorable 切换（敌人 set_dodge/跳跃）时不补发，集合会残留或漏更新（LEARNINGS 556）。
# point_targets[i] 为第 i 段锁定的敌人（留作追踪接口）
var _seg_shapes: Array[CollisionShape2D] = []
var point_targets: Array[Node] = []

# 联机远端驱动：位置插值到网络目标点；由 mod 调用 network_apply_beam_state 置位。
var _net_remote_driven: bool = false
var _net_target_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	PoolManager.add_pool(pool_id, self)
	GameEvents.global_time_count.connect(_time_count)
	_setup_segments()
	_angles = PackedFloat32Array()
	_angles.resize(segment_count)
	var mat := ShaderMaterial.new()
	mat.shader = LASER_SHADER
	line_2d.material = mat
	line_2d_2.material = mat
	player = PlayerRef.resolve(self)
	animation_player.animation_finished.connect(_on_animation_finished)


# 收集场景预置 BeamHitBox 下的 CollisionShape2D（段数由此推导），
# 每个形状 duplicate 成独立 RectangleShape2D，避免 PackedScene 子资源跨实例共享串写。
func _setup_segments() -> void:
	_seg_shapes.clear()
	if beam_hit_box == null:
		segment_count = 0
		point_targets.resize(0)
		return
	for child in beam_hit_box.get_children():
		if child is CollisionShape2D:
			var s := child as CollisionShape2D
			if s.shape != null:
				s.shape = s.shape.duplicate() as Shape2D
			else:
				s.shape = RectangleShape2D.new()
			_seg_shapes.append(s)
	segment_count = _seg_shapes.size()
	point_targets.resize(segment_count)
	_set_segments_active(false)


func follow(muzzle_global: Vector2, aim_angle: float, delta: float) -> void:
	# 非有限输入会把激光自身 transform 污染为 NaN；BeamHitBox 作为子节点，
	# 其全局 transform 即使各形状局部坐标已过滤仍会带 NaN 进 Rapier（LEARNINGS 302-306）。
	if not (muzzle_global.is_finite() and is_finite(aim_angle)):
		return
	global_position = muzzle_global
	if segment_count <= 0:
		return
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
	flight_time = 0.0
	_just_activated = true
	# 每次激活清远端驱动标记：本地无所谓；远端克隆待下一帧状态到达后吸附到正确枪口。
	_net_remote_driven = false
	impact_particles.emitting = true
	impact_particles_2.emitting = true
	grow = 0.0
	animation_player.play("grow")
	_set_segments_active(true)
	update_beam()
	self.scale.x = 1.0


func idle_state() -> void:
	if is_idle == 0:
		ExtensionHooks.notify(ExtensionHooks.on_projectile_despawned, [self])
	is_idle = 1
	enabled = false
	damage_cd = 0
	impact_particles.emitting = false
	impact_particles_2.emitting = false
	animation_player.play_backwards("grow")
	_set_segments_active(false)
	in_idle.emit()


func _set_segments_active(active: bool) -> void:
	for s in _seg_shapes:
		s.disabled = not active


func _on_animation_finished(_anim_name: StringName) -> void:
	if is_idle == 1:
		visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	flight_time += delta
	var hue := base_hue + sin(_time * color_cycle_speed) * hue_range
	line_2d.default_color = Color.from_hsv(hue, 1.0, 10.0, 1.0)
	line_2d_2.default_color = Color.from_hsv(hue, 0.25, 10.0, 1.0)
	var w := (base_width + sin(_time * width_wobble_freq) * width_jitter) * grow
	line_2d.width = w
	line_2d_2.width = max(2.0, w * 0.35)


func _physics_process(delta: float) -> void:
	if is_idle == 1:
		return
	if _net_remote_driven:
		var w := 1.0 - exp(-net_pos_lerp_speed * delta)
		global_position = global_position.lerp(_net_target_pos, w)
	update_beam()


func update_beam() -> void:
	var pts := _build_beam_points()
	if pts.size() < 2:
		pts = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	line_2d.points = pts
	line_2d_2.points = pts
	var beam_end: Vector2 = pts[pts.size() - 1]
	impact_particles.position = beam_end
	impact_particles_2.position = beam_end
	_update_segments(pts)


func _has_tracking_target() -> bool:
	for i in range(1, _track_limit() + 1):
		if _valid_target(i) != null:
			return true
	return false


# 追踪锁敌上限：显式上限与 point_targets 容量取小
func _track_limit() -> int:
	return mini(max_tracked_enemies, point_targets.size() - 1)


func get_max_tracked_enemies() -> int:
	return max_tracked_enemies


func _build_beam_points() -> PackedVector2Array:
	if _has_tracking_target():
		return _build_beam_points_tracking()
	return _build_beam_points_lag()


func _build_beam_points_lag() -> PackedVector2Array:
	if segment_count <= 0:
		return PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
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
			var target_world: Vector2 = target.global_position
			if target_world.is_finite():
				var point_global := global_position + p.rotated(global_rotation)
				local_angle = (target_world - point_global).angle() - global_rotation
		if not is_finite(local_angle):
			local_angle = 0.0
		p += Vector2(seg, 0).rotated(local_angle)
		if not p.is_finite():
			break
		pts.append(p)
	return pts


# 追踪模式：依次抵达每个锁定敌人（链式，最多 max_tracked_enemies 个），
# 再从最后一个敌人沿进入方向直穿到墙（射程 max_length，与链长解耦），
# 整条折线参与伤害结算。
func _build_beam_points_tracking() -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2.ZERO)
	var prev_world := global_position
	# 非有限坐标会让 dir_world / 形状尺寸变成 NaN，进而 panic Rapier（LEARNINGS 302-306）。
	if not prev_world.is_finite():
		return _build_beam_points_lag()
	var dir_world := Vector2.RIGHT.rotated(global_rotation)
	for i in range(1, _track_limit() + 1):
		var target := _valid_target(i)
		if target == null:
			break
		var target_world: Vector2 = target.global_position
		if not target_world.is_finite():
			continue
		var d := target_world - prev_world
		var dist := d.length()
		if dist <= 0.001 or not is_finite(dist):
			continue
		dir_world = d / dist
		pts.append(to_local(target_world))
		prev_world = target_world
	# 末端射墙：与链长解耦，从最后一个敌人沿进入方向射线 max_length
	var to := prev_world + dir_world * max_length
	var hit := _wall_ray(prev_world, to)
	var end_world := to if hit == Vector2.INF else hit
	if end_world.is_finite() and end_world.distance_to(prev_world) > 0.001:
		pts.append(to_local(end_world))
	return pts


func _wall_ray(from: Vector2, to: Vector2) -> Vector2:
	if not (from.is_finite() and to.is_finite()):
		return Vector2.INF
	var space := get_world_2d().direct_space_state
	if space == null:
		return Vector2.INF
	var query := PhysicsRayQueryParameters2D.create(from, to, wall_collision_mask)
	var result := space.intersect_ray(query)
	if result.has("position"):
		return result["position"]
	return Vector2.INF


# 固定使用场景预置形状：有效段贴合折线，超出折线的段退化到端点并 disabled，
# 不再运行期创建/释放 Area2D。
func _update_segments(pts: PackedVector2Array) -> void:
	var used := pts.size() - 1
	var end_point: Vector2 = pts[pts.size() - 1] if pts.size() > 0 else Vector2.ZERO
	for i in range(_seg_shapes.size()):
		var s := _seg_shapes[i]
		var rect := s.shape as RectangleShape2D
		if rect == null:
			continue
		if i < used and i + 1 < pts.size():
			var a := pts[i]
			var b := pts[i + 1]
			if not (a.is_finite() and b.is_finite()):
				if not s.disabled:
					s.disabled = true
				continue
			var d := b - a
			s.position = (a + b) * 0.5
			s.rotation = d.angle()
			rect.size = Vector2(max(d.length(), 1.0), hit_box_width)
			if s.disabled:
				s.disabled = false
		else:
			s.position = end_point
			s.rotation = 0.0
			rect.size = Vector2(1.0, 1.0)
			if not s.disabled:
				s.disabled = true


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
	# 即时重叠为准：目标躲出后不会被残留接触继续命中；躲回光束内也能照常结算。
	for hurtbox in _overlapping_areas():
		if hurtbox == null or not is_instance_valid(hurtbox):
			continue
		# 敌人 set_dodge/跳跃期间 monitorable=false；此期间不结算，落地且仍在光束内则恢复。
		if not hurtbox.monitorable:
			continue
		hurtbox.hit_received.emit(damage_data)
	damage_cd = damage_tick_interval


# 即时重叠查询：直接问物理空间当前哪些启用的段形状覆盖了 HurtBox。
# 不用 Area2D.get_overlapping_areas()（Rapier 下会残留，LEARNINGS 321/463）。
func _overlapping_areas() -> Dictionary:
	var set: Dictionary = {}
	if beam_hit_box == null:
		return set
	var space: PhysicsDirectSpaceState2D = beam_hit_box.get_world_2d().direct_space_state
	if space == null:
		return set
	var params := PhysicsShapeQueryParameters2D.new()
	params.collision_mask = beam_hit_box.collision_mask
	params.collide_with_areas = true
	params.collide_with_bodies = false
	for s in _seg_shapes:
		if s == null or s.disabled or s.shape == null:
			continue
		params.shape = s.shape
		params.transform = s.global_transform
		for r in space.intersect_shape(params, 32):
			var a = r["collider"]
			if a is HurtBox:
				set[a] = true
	return set


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


# 联机：导出光束状态（枪口世界坐标 + 各段角度 + 各段锁定敌人的 net_id，0=无）。
# 供 mod 的 coop 通道按 effect_id 周期广播，使远端克隆能跟随/追踪。
func network_get_beam_state() -> Dictionary:
	var targets := PackedInt32Array()
	for i in range(point_targets.size()):
		var t := point_targets[i]
		if t != null and is_instance_valid(t):
			targets.append(int(t.get_meta("net_id", 0)))
		else:
			targets.append(0)
	return {"p": global_position, "a": _angles.duplicate(), "t": targets}


# 联机：套用远端状态。位置写入目标点由 _physics_process 平滑插值；各段角度直套。
# 锁定目标由 mod 依 net_id 解析成节点后经 set_point_target 写入（本体不依赖 mod 语义）。
func network_apply_beam_state(p: Vector2, angles: PackedFloat32Array) -> void:
	if not p.is_finite():
		return
	_net_target_pos = p
	if not _net_remote_driven:
		_net_remote_driven = true
		global_position = p
	if segment_count > 0 and angles.size() >= segment_count:
		for i in range(segment_count):
			_angles[i] = angles[i]
		global_rotation = _angles[0]


func _exit_tree() -> void:
	if GameEvents.global_time_count.is_connected(_time_count):
		GameEvents.global_time_count.disconnect(_time_count)
