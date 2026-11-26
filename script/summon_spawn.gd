class_name SummonSpawn
extends RefCounted

## 召唤物安全落点：以玩家（或给定锚点）为中心，在环形范围内选一个“可行走 + 不贴墙”的点。
##
## 设计要点：
## - 上限半径 < 壁垒的玩家避让半径（barricade.tscn 的 avoid_player_start_radius=64），
##   这样落点必在壁垒给玩家让出的空地里；即使建墙发生在落点之后，召唤物自身位置也会
##   被壁垒的召唤物避让（avoid_summoned_radius=80）覆盖。
## - 查询墙体的时机不可靠（壁垒在 round_start 之后才建墙），所以“能否落点”是尽力而为：
##   拓扑不可用时只压地图外边界；墙生效后由 SummonedManager 再复检一次。
## - 纯函数 pick_in_ring 允许注入 accept 回调，便于 headless 探针测试。
##
## 不依赖 get_tree()：需要树时才由调用方传入 `from`（用于取玩家/中心锚点）。

## 落点离地图外边界的内推余量（与 spawn_anim / MapBounds 的回位口径一致）。
const MAP_MARGIN := 24.0
## 随机采样的尝试次数；失败后退到确定性槽位。
const ATTEMPTS := 20
## 确定性补位角度数（随机采样全失败时按均匀角度再试）。
const SLOT_COUNT := 12
## 间距放宽下限：召唤物本体半径约 20，低于 28 会明显重叠。
const MIN_SEPARATION_FLOOR := 28.0
## 默认最小间距（两个 20 半径的召唤物不重叠，再留一点余量）。
const DEFAULT_MIN_SEPARATION := 44.0
## 锚点兜底（找不到玩家与场景中心时，与原炮台写死点保持一致）。
const FALLBACK_ANCHOR := Vector2(704, 448)


## 当前玩家锚点：玩家 → 组 CenterPosition（BattleRoom）→ 调用方的 spawn_point → 写死兜底。
static func player_anchor(from: Node) -> Vector2:
	var player := PlayerRef.resolve(from)
	if player is Node2D:
		return (player as Node2D).global_position
	if from != null and is_instance_valid(from) and from.is_inside_tree():
		var tree := from.get_tree()
		if tree != null:
			var center := tree.get_first_node_in_group("CenterPosition")
			if center is Node2D:
				return (center as Node2D).global_position
		var fallback = from.get("spawn_point")
		if fallback is Vector2 and (fallback as Vector2).is_finite():
			return fallback as Vector2
	return FALLBACK_ANCHOR


## 玩家附近的落点（radius.x=最小半径，radius.y=最大半径）。
static func near_player(from: Node, radius: Vector2, avoid: Array = [], min_sep: float = DEFAULT_MIN_SEPARATION) -> Vector2:
	return near_anchor(player_anchor(from), radius, avoid, min_sep)


## 指定锚点附近的落点；所有候选都不合法时退到最近 body-safe 点，再退到锚点。
static func near_anchor(anchor: Vector2, radius: Vector2, avoid: Array = [], min_sep: float = DEFAULT_MIN_SEPARATION) -> Vector2:
	if not anchor.is_finite():
		return anchor
	var lo := maxf(0.0, minf(radius.x, radius.y))
	var hi := maxf(lo, maxf(radius.x, radius.y))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var picked := pick_in_ring(anchor, lo, hi, avoid, min_sep, Callable(), rng)
	if picked.is_finite():
		return picked
	# 召唤物数量多、环形被占满时先放宽间距，避免整批退到远处。
	var relaxed := maxf(MIN_SEPARATION_FLOOR, min_sep * 0.6)
	if relaxed < min_sep:
		picked = pick_in_ring(anchor, lo, hi, avoid, relaxed, Callable(), rng)
		if picked.is_finite():
			return picked
	# 兜底：最近 body-safe 格（可能与玩家拉开距离，但保证不嵌墙）。
	var safe := EnemyNavField.nearest_body_safe_point(anchor, 1)
	safe = MapBounds.nearest_inside(safe, MAP_MARGIN)
	if safe.is_finite() and not is_blocked(safe):
		return safe
	return MapBounds.nearest_inside(anchor, MAP_MARGIN)


## 环内找一个满足 accept / 间距的候选点；找不到返回 Vector2.INF（纯函数，可单测）。
## accept 为空时用默认的 _is_placeable（地图内 + 非 solid + body-safe）；
## 传入自定义 accept 时由调用方负责全部校验（探针/测试用）。
static func pick_in_ring(anchor: Vector2, rmin: float, rmax: float, avoid: Array, min_sep: float, accept: Callable, rng: RandomNumberGenerator) -> Vector2:
	if not anchor.is_finite():
		return Vector2.INF
	var lo := maxf(0.0, minf(rmin, rmax))
	var hi := maxf(lo, maxf(rmin, rmax))
	var generator := rng
	if generator == null:
		generator = RandomNumberGenerator.new()
		generator.randomize()
	for _i in ATTEMPTS:
		var angle := generator.randf_range(0.0, TAU)
		var dist := generator.randf_range(lo, hi)
		var candidate := anchor + Vector2(cos(angle), sin(angle)) * dist
		if _acceptable(candidate, avoid, min_sep, accept):
			return candidate
	# 随机全失败：确定性槽位兜底，保证同一锚点一定有机会落点。
	for slot in SLOT_COUNT:
		var angle := TAU * float(slot) / float(SLOT_COUNT)
		for dist in [hi, (lo + hi) * 0.5, lo]:
			var candidate := anchor + Vector2(cos(angle), sin(angle)) * float(dist)
			if _acceptable(candidate, avoid, min_sep, accept):
				return candidate
	return Vector2.INF


## 某个世界点是否被当前场地阻挡覆盖（落在 solid 格或贴着墙、身体放不下）。
## 没有 NavObstacle / 显式阻挡时零开销返回 false；拓扑建不起来时也按“不阻塞”处理。
static func is_blocked(world_pos: Vector2) -> bool:
	if not world_pos.is_finite():
		return true
	if not EnemyNavField.has_blocks():
		return false
	if not EnemyNavField.ensure_topology():
		return false
	if EnemyNavField.is_solid(world_pos):
		return true
	return not EnemyNavField.is_body_safe(world_pos, 1)


## 场上有效召唤物的位置（跳过 idle 与联机远端镜像），供生成/归位时做间距避让。
static func summon_positions(from: Node) -> Array:
	var out: Array = []
	if from == null or not is_instance_valid(from) or not from.is_inside_tree():
		return out
	var tree := from.get_tree()
	if tree == null:
		return out
	for node in tree.get_nodes_in_group("Summoned"):
		if node == null or not is_instance_valid(node) or not (node is Node2D):
			continue
		if node.is_queued_for_deletion():
			continue
		var idle = node.get("is_idle")
		if idle != null and int(idle) == 1:
			continue
		if node.has_meta("is_local_summoned") and not bool(node.get_meta("is_local_summoned")):
			continue
		out.append((node as Node2D).global_position)
	return out


static func _acceptable(candidate: Vector2, avoid: Array, min_sep: float, accept: Callable) -> bool:
	if not candidate.is_finite():
		return false
	if accept.is_valid():
		if not bool(accept.call(candidate)):
			return false
	elif not _is_placeable(candidate):
		return false
	if min_sep <= 0.0:
		return true
	var min_sq := min_sep * min_sep
	for other in avoid:
		if other is Vector2 and (other as Vector2).distance_squared_to(candidate) < min_sq:
			return false
	return true


## 默认落点校验：整本体在地图内（nearest_inside 不再需要挪动）+ 不在墙里/不贴墙。
static func _is_placeable(world_pos: Vector2) -> bool:
	if not world_pos.is_finite():
		return false
	var clamped := MapBounds.nearest_inside(world_pos, MAP_MARGIN)
	if clamped.distance_squared_to(world_pos) > 0.25:
		return false
	return not is_blocked(world_pos)
