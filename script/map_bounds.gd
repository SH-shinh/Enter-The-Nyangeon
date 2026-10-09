extends Node

## 地图出界安全网：把越界的玩家 / 敌人 / 召唤物拉回地图内最近点。
## 由 GameEvents.global_time_count（0.1s）驱动，每 TICK_INTERVAL 个 tick（≈1s）检查一次；
## 仅在出界时做最近点计算，平时为 O(边数) 多边形判定，避免逐帧开销。
## 边界取自物理墙 FloorWall（碰撞层 WALL_MASK）内壁：从地图中心向四个轴方向射射线，
## 取命中点构成菱形可行走边界。这样不会误伤贴墙的正常单位；射线失败时回退到
## 组 "Map"（SpawnMap）used cells 的凸包。

const TICK_INTERVAL := 10 # 0.1s * 10 = 1s
const OUT_MARGIN := 24.0 # 圆心越过墙该距离才算真出界（贴墙/轻微挤压不触发）
const INSET := 8.0 # 回位落点在半径基础上再向中心内推，多留余量
const WALL_MASK := 256 # FloorWall 碰撞层（玩家唯一会碰撞的地图墙）
const RAY_LEN := 4000.0 # 从地图中心向外的射线长度，需覆盖整张竞技场

var _tilemap: Node = null
var _hull := PackedVector2Array()
var _outer_hull := PackedVector2Array() # _hull 外扩 OUT_MARGIN，用于触发判定
var _center := Vector2.ZERO
var _tick: int = 0
var _erode_cache: Dictionary = {} # ceil(半径/4) -> 内缩后的多边形（落点用）

func _ready() -> void:
	GameEvents.global_time_count.connect(_on_tick)

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
	var player := tree.get_first_node_in_group("Player")
	if player != null and is_instance_valid(player):
		_resolve(player)
	for enemy in PoolManager.get_active_enemies():
		if enemy != null and is_instance_valid(enemy):
			_resolve(enemy)
	for summoned in tree.get_nodes_in_group("Summoned"):
		if summoned == null or not is_instance_valid(summoned):
			continue
		if summoned.get("is_idle") == 1:
			continue
		_resolve(summoned)

func _resolve(entity: Node2D) -> void:
	var pos: Vector2 = entity.global_position
	if not _is_out(pos):
		return
	var radius := _body_radius(entity)
	entity.global_position = nearest_inside(pos, radius)
	if entity is CharacterBody2D:
		entity.velocity = Vector2.ZERO

# 触发判定：与体型无关，只与真实边界外扩 OUT_MARGIN 对比（贴墙不触发）
func _is_out(pos: Vector2) -> bool:
	var poly := _outer_hull if _outer_hull.size() >= 3 else _hull
	if poly.size() < 3:
		return false
	return not _point_in_polygon(pos, poly)

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
	if _tilemap != null and is_instance_valid(_tilemap) and _hull.size() >= 3:
		return
	var tree := get_tree()
	if tree == null:
		return
	_tilemap = tree.get_first_node_in_group("Map")
	_hull = PackedVector2Array()
	_outer_hull = PackedVector2Array()
	_erode_cache.clear()
	if _tilemap == null or not is_instance_valid(_tilemap):
		return
	var fallback := _spawnmap_hull()
	var center := _get_center(tree, fallback)
	var hits := _raycast_walls(tree, center)
	_hull = _diamond_from_hits(hits) if hits.size() == 4 else fallback
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
func _raycast_walls(tree: SceneTree, center: Vector2) -> Array:
	var space := tree.root.world_2d.direct_space_state
	var dirs := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	var hits: Array = []
	for d in dirs:
		var query := PhysicsRayQueryParameters2D.create(center, center + d * RAY_LEN, WALL_MASK)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return []
		hits.append(hit.position)
	return hits

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
