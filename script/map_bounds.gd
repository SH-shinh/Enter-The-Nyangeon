extends Node

## 地图出界安全网：把越界的玩家 / 敌人 / 召唤物拉回地图内最近点。
## 由 GameEvents.global_time_count（0.1s）驱动，每 TICK_INTERVAL 个 tick（≈1s）检查一次；
## 仅在出界时做最近点计算，平时为 O(边数) 多边形判定，避免逐帧开销。
## 边界取自物理墙 FloorWall（碰撞层 WALL_MASK）内壁：从地图中心向四个轴方向射射线，
## 取命中点构成菱形可行走边界。这样不会误伤贴墙的正常单位；射线失败时回退到
## 组 "Map"（SpawnMap）used cells 的凸包。
##
## 兜底边界（SpawnMap 凸包）比真实墙内壁小一圈，**不可当稳定结果永久缓存**：
## 场景刚装载、物理还未就绪时首帧调用（如 R1 场地词条 start()）会让射线全部 miss，
## 之后每次调用都要重试，直到 boundary_source == "walls"。
## 触发判定：正常（walls）沿用 _outer_hull；只有兜底边界才改用"中心→实体"墙射线，
## 避免兜底期间贴墙被误拉（详见 _resolve）。

const TICK_INTERVAL := 10 # 0.1s * 10 = 1s
const OUT_MARGIN := 24.0 # 圆心越过墙该距离才算真出界（贴墙/轻微挤压不触发）
const INSET := 8.0 # 回位落点在半径基础上再向中心内推，多留余量
const WALL_MASK := 256 # FloorWall 碰撞层（玩家唯一会碰撞的地图墙）
const RAY_LEN := 4000.0 # 从地图中心向外的射线长度，需覆盖整张竞技场

var _tilemap: Node = null
var _map_instance_id: int = 0
var _hull := PackedVector2Array()
var _outer_hull := PackedVector2Array() # _hull 外扩 OUT_MARGIN，用于触发判定
var _boundary_source: StringName = &""
var _center := Vector2.ZERO
var _tick: int = 0
var _check_count: int = 0
var _erode_cache: Dictionary = {} # ceil(半径/4) -> 内缩后的多边形（落点用）
var _retry_physics_frame: int = -1 # 兜底边界重试射线：同一物理帧只试一次
var _fallback_warned := false
var _pull_lock: Dictionary = {} # instance_id -> 拉回后跳过的 check 序号

func _ready() -> void:
	GameEvents.global_time_count.connect(_on_tick)
	GameEvents.first_round_add.connect(invalidate)

func invalidate() -> void:
	_tilemap = null
	_map_instance_id = 0
	_hull = PackedVector2Array()
	_outer_hull = PackedVector2Array()
	_boundary_source = &""
	_center = Vector2.ZERO
	_erode_cache.clear()
	_fallback_warned = false
	_pull_lock.clear()

func _on_tick() -> void:
	_tick += 1
	if _tick < TICK_INTERVAL:
		return
	_tick = 0
	_check_out_of_map()

func _check_out_of_map() -> void:
	_ensure_hull()
	if _hull.size() < 3:
		return
	var tree := get_tree()
	if tree == null:
		return
	_check_count += 1
	_prune_pull_lock()
	# 只有场景里确实存在 NavObstacle/注册阻挡时才建拓扑，平时保持原来的外边界开销。
	var internal_walls: bool = EnemyNavField.has_blocks() and EnemyNavField.ensure_topology()
	var player := tree.get_first_node_in_group("Player")
	if player != null and is_instance_valid(player):
		_resolve(player, internal_walls)
	for enemy in PoolManager.get_active_enemies():
		if enemy != null and is_instance_valid(enemy):
			_resolve(enemy, internal_walls)
	for summoned in tree.get_nodes_in_group("Summoned"):
		if summoned == null or not is_instance_valid(summoned):
			continue
		if summoned.get("is_idle") == 1:
			continue
		_resolve(summoned, internal_walls)
	for boss in tree.get_nodes_in_group("BOSS"):
		if boss is Node2D and is_instance_valid(boss) and not boss.is_queued_for_deletion():
			_resolve(boss, internal_walls)
	# 医疗包也是会被墙覆盖的实体；放在这里统一走回位/卡墙兜底。
	for item in tree.get_nodes_in_group("HealthItem"):
		if item is Node2D and is_instance_valid(item) and not item.is_queued_for_deletion():
			_resolve(item, internal_walls)

func _resolve(entity: Node2D, internal_walls: bool = false) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var pos: Vector2 = entity.global_position
	# 正常边界：沿用已调好的外扩多边形判定与落点，行为不变。
	if _boundary_source == &"walls":
		if _is_out(pos):
			_apply_pull(entity, nearest_inside(pos, _body_radius(entity)), pos)
			return
		if internal_walls:
			_resolve_internal_stuck(entity, pos)
		return
	# 兜底边界不可信：用"中心→实体"墙射线判断。贴墙时实体在墙内，不会误拉。
	var crossing := _wall_crossing(pos)
	if crossing.is_empty():
		if internal_walls:
			_resolve_internal_stuck(entity, pos)
		return
	if not is_beyond_wall(float(crossing["entity_dist"]), float(crossing["wall_dist"]), OUT_MARGIN):
		if internal_walls:
			_resolve_internal_stuck(entity, pos)
		return
	var radius := _body_radius(entity)
	var dir: Vector2 = crossing["dir"]
	var hit_pos: Vector2 = crossing["position"]
	var landing := hit_pos - dir * (radius + INSET)
	if not landing.is_finite():
		return
	_apply_pull(entity, landing, pos)

# 内部墙体（NavObstacle/barricade）卡住：中心格 solid 时拉到最近 body-safe 格。
# 只认 solid，贴墙但不进格不触发；落点仍 solid 则放弃，交给下一次 tick。
func _resolve_internal_stuck(entity: Node2D, pos: Vector2) -> void:
	if not EnemyNavField.is_solid(pos):
		return
	var landing := EnemyNavField.nearest_body_safe_point(pos, 1)
	if not landing.is_finite():
		return
	if landing.distance_squared_to(pos) < 0.01:
		return
	if EnemyNavField.is_solid(landing):
		return
	_apply_pull(entity, landing, pos)

func _apply_pull(entity: Node2D, landing: Vector2, from: Vector2) -> void:
	var id := entity.get_instance_id()
	# 拉回后跳过下一次 1s 检查，防止落点被物理再挤出形成 1s 循环。
	if int(_pull_lock.get(id, -1)) >= _check_count:
		return
	entity.global_position = landing
	entity.reset_physics_interpolation()
	if entity is CharacterBody2D:
		entity.velocity = Vector2.ZERO
	_pull_lock[id] = _check_count + 1
	if OS.is_debug_build():
		print("[MapBounds] pull %s from=%s to=%s (boundary=%s)" % [entity.name, from, landing, _boundary_source])

# 纯判定（便于单测）：实体沿射线方向越过墙内壁 margin 像素才算真出界。
func is_beyond_wall(entity_dist: float, wall_dist: float, margin: float) -> bool:
	return entity_dist > wall_dist + margin

# 从地图中心向实体方向射线，返回墙面命中点、距离与方向；未命中返回空字典。
func _wall_crossing(pos: Vector2) -> Dictionary:
	var delta := pos - _center
	if delta.length_squared() < 0.25:
		return {}
	var dir := delta.normalized()
	var hit := _ray_hit(_center, _center + dir * RAY_LEN)
	if hit.is_empty():
		return {}
	var hit_pos: Vector2 = hit.get("position", Vector2.ZERO)
	return {
		"position": hit_pos,
		"dir": dir,
		"wall_dist": _center.distance_to(hit_pos),
		"entity_dist": delta.length(),
	}

func _prune_pull_lock() -> void:
	if _pull_lock.is_empty():
		return
	for id in _pull_lock.keys():
		if int(_pull_lock[id]) < _check_count or not is_instance_id_valid(id):
			_pull_lock.erase(id)

# 触发判定：与体型无关，只与真实边界外扩 OUT_MARGIN 对比（贴墙不触发）
func _is_out(pos: Vector2) -> bool:
	var poly := _outer_hull if _outer_hull.size() >= 3 else _hull
	if poly.size() < 3:
		return false
	return not _point_in_polygon(pos, poly)

func ensure_ready() -> void:
	if _hull.size() < 3 or _boundary_source != &"walls":
		_ensure_hull()

func get_walkable_polygon() -> PackedVector2Array:
	ensure_ready()
	return _hull.duplicate()

func is_inside_walkable(pos: Vector2) -> bool:
	ensure_ready()
	if _hull.size() < 3:
		return false
	return _point_in_polygon(pos, _hull)

func get_boundary_source() -> StringName:
	ensure_ready()
	return _boundary_source

func nearest_inside(pos: Vector2, radius: float = 0.0) -> Vector2:
	var poly := _poly_for_radius(radius)
	if poly.size() < 3 or _point_in_polygon(pos, poly):
		return pos
	var best := pos
	var best_d := INF
	var n := poly.size()
	for i in n:
		var cp := Geometry2D.get_closest_point_to_segment(pos, poly[i], poly[(i + 1) % n])
		var d := pos.distance_squared_to(cp)
		if d < best_d:
			best_d = d
			best = cp
	var dir := _center - best
	if dir.length_squared() > 0.0001:
		best += dir.normalized() * INSET
	return best

# 按实体碰撞半径把边界多边形向内缩（Minkowski erosion，4px 分桶缓存），
# 使回位后整个本体都在墙内、不再被挤出。半径<=半格用原多边形。
func _poly_for_radius(radius: float) -> PackedVector2Array:
	if _hull.size() < 3 or radius <= 0.5:
		return _hull
	var key := int(ceil(radius * 0.25))
	if _erode_cache.has(key):
		return _erode_cache[key]
	var poly := PackedVector2Array()
	var result := Geometry2D.offset_polygon(_hull, -float(key) * 4.0, Geometry2D.JOIN_MITER)
	if result.size() > 0 and result[0].size() >= 3:
		poly = result[0]
	_erode_cache[key] = poly
	return poly

# 实体本体的碰撞半径：取直接子节点 CollisionShape2D/Polygon2D 的外接半径最大值
# （不取 HurtBox/PickBox 等 Area 下的形状，也避开 Player.collision_shape_2d 实为 PickBox 的坑）
func _body_radius(entity: Node2D) -> float:
	var r := 0.0
	for c in entity.get_children():
		var s := 1.0
		if c is Node2D:
			var sc: Vector2 = c.global_scale
			s = maxf(absf(sc.x), absf(sc.y))
		if c is CollisionShape2D and c.shape != null:
			r = maxf(r, _shape_extent(c.shape) * s)
		elif c is CollisionPolygon2D:
			r = maxf(r, _polygon_extent(c.polygon) * s)
	return r

func _shape_extent(shape: Shape2D) -> float:
	if shape is CircleShape2D:
		return shape.radius
	if shape is RectangleShape2D:
		return shape.size.length() * 0.5
	if shape is CapsuleShape2D:
		return maxf(shape.radius, shape.height * 0.5)
	if shape is ConvexPolygonShape2D:
		return _polygon_extent(shape.points)
	if shape is SegmentShape2D:
		return shape.a.distance_to(shape.b) * 0.5
	return 0.0

func _polygon_extent(points: PackedVector2Array) -> float:
	if points.is_empty():
		return 0.0
	var rect := Rect2(points[0], Vector2.ZERO)
	for p in points:
		rect = rect.expand(p)
	return rect.size.length() * 0.5

# 与绕序无关的射线法（凸包点序不作保证）
func _point_in_polygon(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var a := poly[i]
		var b := poly[j]
		if (a.y > p.y) != (b.y > p.y):
			if p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x:
				inside = not inside
		j = i
	return inside

func _ensure_hull() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var map := tree.get_first_node_in_group("Map")
	if map == null or not is_instance_valid(map):
		_tilemap = null
		_map_instance_id = 0
		_hull = PackedVector2Array()
		_outer_hull = PackedVector2Array()
		_boundary_source = &""
		_erode_cache.clear()
		return
	var map_id: int = map.get_instance_id()
	# 只有 walls 才是稳定结果；兜底边界每次调用都要允许重试射线。
	var needs_rebuild := _tilemap != map or _map_instance_id != map_id \
		or not is_instance_valid(_tilemap) or _hull.size() < 3 \
		or _boundary_source != &"walls"
	if not needs_rebuild:
		return
	var frame := Engine.get_physics_frames()
	if _boundary_source != &"walls" and _hull.size() >= 3 and _retry_physics_frame == frame:
		return
	_retry_physics_frame = frame
	_tilemap = map
	_map_instance_id = map_id
	_hull = PackedVector2Array()
	_outer_hull = PackedVector2Array()
	_boundary_source = &""
	_erode_cache.clear()
	var fallback := _spawnmap_hull()
	var center := _get_center(tree, fallback)
	var hits := _raycast_walls(center)
	if hits.size() == 4:
		_hull = _diamond_from_hits(hits)
		_boundary_source = &"walls"
		_fallback_warned = false
	else:
		_hull = fallback
		_boundary_source = &"spawnmap" if _hull.size() >= 3 else &""
		if _boundary_source == &"spawnmap" and not _fallback_warned:
			_fallback_warned = true
			push_warning("MapBounds: wall raycast failed; using SpawnMap fallback (smaller than the walkable area). center=%s" % center)
	if _hull.size() < 3:
		return
	_center = Vector2.ZERO
	for p in _hull:
		_center += p
	_center /= float(_hull.size())
	_outer_hull = _expand(_hull, OUT_MARGIN)

# 触发边界：把 _hull 向外扩 margin（负 delta 为内缩，正为外扩）
func _expand(poly: PackedVector2Array, margin: float) -> PackedVector2Array:
	if poly.size() < 3 or margin <= 0.0:
		return poly
	var result := Geometry2D.offset_polygon(poly, margin, Geometry2D.JOIN_MITER)
	if result.size() > 0 and result[0].size() >= 3:
		return result[0]
	return poly

# 地图中心：优先组 "CenterPosition"（BattleRoom），否则用回退多边形的质心
func _get_center(tree: SceneTree, fallback: PackedVector2Array) -> Vector2:
	var marker := tree.get_first_node_in_group("CenterPosition")
	if marker is Node2D:
		return marker.global_position
	if fallback.size() >= 3:
		var c := Vector2.ZERO
		for p in fallback:
			c += p
		return c / float(fallback.size())
	return Vector2.ZERO

# 从中心向 ±x / ±y 射射线，命中 FloorWall 内壁；全部命中才返回 4 个点
func _raycast_walls(center: Vector2) -> Array:
	var dirs := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	var hits: Array = []
	for d in dirs:
		var hit := _ray_hit(center, center + d * RAY_LEN)
		if hit.is_empty():
			return []
		hits.append(hit["position"])
	return hits

# 单条墙射线（测试可覆写 _ray_hit）。
func _ray_hit(from: Vector2, to: Vector2) -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {}
	var space := tree.root.world_2d.direct_space_state
	if space == null:
		return {}
	var query := PhysicsRayQueryParameters2D.create(from, to, WALL_MASK)
	return space.intersect_ray(query)

# 命中点顺序为 [上, 右, 下, 左]，直接构成菱形边界
func _diamond_from_hits(hits: Array) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for p in hits:
		poly.append(p)
	return poly

# 预检用：SpawnMap used cells 凸包（射线失败时的回退边界）
func _spawnmap_hull() -> PackedVector2Array:
	if _tilemap == null or not is_instance_valid(_tilemap) or not _tilemap.has_method("get_used_cells"):
		return PackedVector2Array()
	var cells: Array = _tilemap.get_used_cells(0)
	if cells.is_empty():
		return PackedVector2Array()
	var points := PackedVector2Array()
	points.resize(cells.size())
	for i in cells.size():
		points[i] = _tilemap.to_global(_tilemap.map_to_local(cells[i]))
	var hull := Geometry2D.convex_hull(points)
	# convex_hull 返回闭合环（首尾重复），去掉重复点以免质心偏移
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	if hull.size() < 3:
		hull = _bounds_polygon(points)
	return hull

# 退化兜底：用点集包围盒构造矩形
func _bounds_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var rect := Rect2(points[0], Vector2.ZERO)
	for p in points:
		rect = rect.expand(p)
	return PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y),
	])
