class_name EnemyAI

## 敌人 AI 的 5Hz 求解编排（静态服务，不注册 autoload）。
##
## 统一决策管线：
##   1. 密度场：把全部 AI 敌人 splat 成一张拥挤度场，算出每只的「横向散开推力」。
##   2. 分桶：按目标玩家分组，分别给近战 / 远程下发「意图 + 目标点(方位角, 半径)」。
##       近战：CHASE（攻击位）/ RING（包围位）/ CUTOFF（封堵位）
##       远程：CHASE（接近）/ KITE（后撤）/ HOLD（驻守射击）/ REPOS（换位找视线）
##   3. 脱困：连续 1 秒没有位移的敌人会被标记 UNSTUCK，由 Enemy 侧接管 0.8 秒。
##   4. 预判：提供 predict_anchor，让导航场种子落在玩家前方。
##
## 注意：这里刻意不引用 Enemy 类型（只用 duck typing），避免与 entity_ENEMY.gd
## 形成 class_name 循环引用；意图常量必须与 Enemy.AIIntent 的枚举顺序一致。

const SOLVE_INTERVAL_MS := 200
const FAN_BASE := 0.18
const SEP_BASE := 0.20

const ROLE_NONE := 0
const ROLE_MELEE := 1

const INTENT_NONE := 0
const INTENT_CHASE := 1
## 近战环带：到自己的同心环半径后沿切向归位（只进不退）。
const INTENT_RING := 2
const INTENT_CUTOFF := 3
const INTENT_RUSH := 4
const INTENT_KITE := 5
const INTENT_HOLD := 6
const INTENT_REPOS := 7
const INTENT_UNSTUCK := 8

const MAX_SLOTS := 8
# 战术分层人数上限（每个目标各自计）：超出这一数量后，远的只走纯场流，不参与角色/槽位/密度/反排队。
# 目的是把 200ms 一次的求解尖峰**封顶**，89 只与 200 只成本相同。
const TACTICAL_LIMIT := 60
const SLOT_SPACING := 28.0
const SLOT_SMOOTH := 0.35
const BASE_SMOOTH := 0.25

# 角色评分：位置 + 速度 + 当前角色留任加成（防抖）
const ROLE_HYSTERESIS := 0.15
const CLOSING_REF := 140.0
const ETA_REF := 2.0
const RANGED_DANGER_SPEED := 120.0
# 场流兜底：直线被挡时才用场流，且做两点平均压掉等距格的对角锯齿
const FLOW_LOOKAHEAD := 26.0
# 切向死区：方位差在 ±3° 内不再施加切向，掐掉"过冲→反向"的极限环
const TANGENT_DEADZONE := 0.05

# 近战同心环：环间距要 > 体宽，环内按弧长算容量（人多自动往外扩圈）
const RING_SPACING := 34.0
const RING_SLOT_SIZE := 32.0
# 槽点搜索：向内收缩 / 向外增长都允许（墙边、角落时"往外挪"才有空间）
const SLOT_GROW_RATIO := 1.18
const SLOT_GROW_MAX_STEPS := 8
const SLOT_MAX_RADIUS := 420.0
# 自由弧采样数（11.25°/点）
const ARC_SAMPLES := 32
# 横向合力上限（相对径向 1.0）：超过就按比例压回去，保证任何时候都在"靠近"
const LATERAL_CAP := 0.6
# 环带被前排挡住时的径向衰减上限（1.0 = 完全停推）
const QUEUE_DAMP := 0.8

# 反排队：正前方 72px 内、夹角 35° 以内且有同类更靠近目标 → 横向推开
const QUEUE_RADIUS := 72.0
const QUEUE_COS := 0.819
# 反排队空间哈希桶边长：必须 > QUEUE_RADIUS（3×3 邻桶才覆盖全部候选）
const QUEUE_BUCKET := 80.0

# 密度场：世界空间均匀网格（与等距瓦片无关）
const DENSITY_CELL := 32.0
const DENSITY_FALLOFF := 64.0
# 背离目标的分量保留比例：0 = 只横散、绝不对抗接近
const DENSITY_BACKPRESSURE := 0.0
# 推力幅度参考：|acc| 达到该值时推力才到满强度（稀疏时≈0）
const DENSITY_MAG_REF := 2.5

# 槽点可行走性：半径逐级收缩到可行走区（含内壁余量），收不下去就不下发槽位
const SLOT_SHRINK_RATIO := 0.8
const SLOT_SHRINK_MAX_STEPS := 12
const SLOT_WALL_MARGIN := 24.0

# 离墙力：8 方向 × 2 距离的探针
const WALL_PROBE_NEAR := 22.0
const WALL_PROBE_FAR := 40.0
const WALL_PUSH_WEIGHT := 0.75

# 视线
const LOS_STEP := 24.0
const LOS_SKIP := 40.0

# 脱困
const STUCK_EPSILON := 6.0
const STUCK_SOLVES := 4
const UNSTUCK_TICKS := 8

const PREDICT_VEL_MIN := 40.0
const PREDICT_VEL_LIMIT := 260.0
const PREDICT_FULL_SPEED := 200.0
const PREDICT_CLAMP_RADIUS := 24.0

static var _last_solve_ms: int = -99999
static var _candidates: Array[Enemy] = []
# 求解上下文快照（与 _candidates 同序）：热路径不再逐敌读 global_position / velocity / _ai_intent
static var _ctx_pos := PackedVector2Array()
static var _ctx_vel := PackedVector2Array()
static var _ctx_intent := PackedInt32Array()
# predict_anchor 缓存（同一帧里所有敌人算的是同一个落点）
static var _anchor_target_id: int = 0
static var _anchor_lead: float = -1.0
static var _anchor_pos: Vector2 = Vector2.ZERO
static var _anchor_vel: Vector2 = Vector2.ZERO
static var _anchor_value: Vector2 = Vector2.ZERO
# target_instance_id -> {"node": Node2D, "all": Array, "melee": Array, "ranged": Array,
#                        "base": float, "cut_dir": float}
static var _groups: Dictionary = {}
# Vector2i -> 密度
static var _density: Dictionary = {}

const INTENT_NAMES := [
	"NONE", "CHASE", "RING", "CUTOFF", "RUSH", "KITE", "HOLD", "REPOS", "UNSTUCK",
]


# ---------------- 调试可视化只读入口（不要修改返回值） ----------------

# 当前密度场（Vector2i -> float）。每 200ms 重建一次，读到的是一次求解的快照。
static func debug_density() -> Dictionary:
	return _density


# 当前参与 AI 求解的敌人列表（已过滤掉 Boss / 路线型 / 客机镜像等）。
static func debug_candidates() -> Array:
	return _candidates


# 候选快照（与 debug_candidates() 同序）。
static func debug_positions() -> PackedVector2Array:
	return _ctx_pos


static func intent_name(intent: int) -> String:
	if intent < 0 or intent >= INTENT_NAMES.size():
		return "?"
	return INTENT_NAMES[intent]


# 当前近战环带被限制的自由弧（调试可视化用）：{anchor, start, span, radius}
static func debug_arc() -> Dictionary:
	for key in _groups:
		var group: Dictionary = _groups[key]
		if not group.has("arc_start"):
			continue
		var node = group.get("node")
		if node == null or not is_instance_valid(node):
			continue
		return {
			"anchor": node.global_position,
			"start": float(group["arc_start"]),
			"span": float(group["arc_span"]),
			"radius": float(group.get("arc_radius", 0.0)),
		}
	return {}


# ---------------- 预判 ----------------

# 目标当前速度（已做阈值与上限处理；镜像没有 velocity 时返回 ZERO）。
static func target_velocity(target) -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	var raw = target.get("velocity")
	if not (raw is Vector2):
		return Vector2.ZERO
	var velocity: Vector2 = raw
	if velocity.length_squared() < PREDICT_VEL_MIN * PREDICT_VEL_MIN:
		return Vector2.ZERO
	return velocity.limit_length(PREDICT_VEL_LIMIT)


# 预判锚点：玩家位置 + 速度 × 提前量（按速度比例缩放，并夹回可行走区）。
static func predict_anchor(target: Node2D, lead_seconds: float) -> Vector2:
	if target == null or not is_instance_valid(target):
		return Vector2.ZERO
	var position: Vector2 = target.global_position
	if lead_seconds <= 0.0:
		return position
	var velocity := target_velocity(target)
	var target_id := target.get_instance_id()
	# 同一帧内所有敌人算的是同一个落点：按 (target, lead, 位置, 速度) 精确缓存，
	# 命中时跳过 MapBounds.nearest_inside（≈1µs）。位置/速度变了就重算，语义与未缓存完全一致。
	if target_id == _anchor_target_id and lead_seconds == _anchor_lead \
			and position == _anchor_pos and velocity == _anchor_vel:
		return _anchor_value
	var predicted: Vector2
	if velocity == Vector2.ZERO:
		predicted = position
	else:
		var scale := clampf(velocity.length() / PREDICT_FULL_SPEED, 0.0, 1.0)
		predicted = MapBounds.nearest_inside(
			position + velocity * lead_seconds * scale, PREDICT_CLAMP_RADIUS)
	_anchor_target_id = target_id
	_anchor_lead = lead_seconds
	_anchor_pos = position
	_anchor_vel = velocity
	_anchor_value = predicted
	return predicted


# ---------------- 求解入口 ----------------

static func ensure_solved(target: Node2D, lead_seconds: float = 0.0) -> void:
	if target == null or not is_instance_valid(target):
		return
	var now := Time.get_ticks_msec()
	if now - _last_solve_ms < SOLVE_INTERVAL_MS:
		return
	_last_solve_ms = now
	if not EnemyNavField.has_blocks() and not _any_enemy_has_profile():
		return
	solve_now(lead_seconds)


static func solve_now(lead_seconds: float = 0.0) -> void:
	_collect()
	if _candidates.is_empty():
		return
	_build_density()
	_apply_density_push()
	_apply_wall_push()
	for key in _groups:
		var group: Dictionary = _groups[key]
		var node = group.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var lead: float = lead_seconds
		if lead <= 0.0:
			lead = _group_lead(group)
		var anchor := predict_anchor(node, lead)
		EnemyNavField.ensure_rebuilt(node, anchor)
		_assign_melee_slots(group, anchor)
		_assign_ranged_slots(group, anchor)
	_update_stuck()


static func _any_enemy_has_profile() -> bool:
	if PoolManager == null:
		return false
	for enemy in PoolManager.get_active_enemies():
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.get("ai_profile") != null:
			return true
	return false


# ---------------- 分桶 ----------------

static func _collect() -> void:
	_candidates.clear()
	_ctx_pos.clear()
	_ctx_vel.clear()
	_ctx_intent.clear()
	if PoolManager == null:
		_groups.clear()
		return
	# 复用分组条目：base / cut_dir 是跨求解的平滑缓存，清空会让"对称包围时基准角恒为 0"。
	for key in _groups:
		var existing: Dictionary = _groups[key]
		existing["all"] = []
		existing["melee"] = []
		existing["ranged"] = []
	var seen: Dictionary = {}
	for raw_enemy in PoolManager.get_active_enemies():
		var enemy := raw_enemy as Enemy
		if enemy == null or not _is_candidate(enemy):
			continue
		var target := _resolve_target(enemy)
		if target == null:
			continue
		_candidates.append(enemy)
		_ctx_pos.append(enemy.global_position)
		_ctx_vel.append(enemy.velocity)
		_ctx_intent.append(enemy._ai_intent)
		var key := target.get_instance_id()
		var group = _groups.get(key)
		if group == null:
			group = {"node": target, "all": [], "melee": [], "ranged": []}
			_groups[key] = group
		group["node"] = target
		group["all"].append(enemy)
		if enemy.ai_role == ROLE_MELEE:
			group["melee"].append(enemy)
		else:
			group["ranged"].append(enemy)
		seen[key] = true
	for key in _groups.keys():
		if not seen.has(key):
			_groups.erase(key)
		else:
			_trim_group(_groups[key])


# 战术分层人数上限（每个目标各自计）：只让最近的 TACTICAL_LIMIT 只参与角色/槽位/密度/反排队，
# 其余清掉意图，`ai_steer` 会退回纯场流（`_steer_intent` 对 INTENT_NONE 直接返回 flow）。
# 这样 200ms 一次的求解尖峰与人数脱钩（89 只和 200 只成本相同）。
static func _trim_group(group: Dictionary) -> void:
	var all_list: Array = group.get("all", [])
	var limit := TACTICAL_LIMIT
	if all_list.size() <= limit:
		for enemy in all_list:
			enemy._ai_tactical = true
		return
	var node = group.get("node")
	if node == null or not is_instance_valid(node) or not (node is Node2D):
		return
	var anchor: Vector2 = (node as Node2D).global_position
	var keys := PackedFloat32Array()
	keys.resize(all_list.size())
	for i in all_list.size():
		keys[i] = (all_list[i] as Enemy).global_position.distance_squared_to(anchor)
	var order := _sorted_indices(keys, false)
	var keep := PackedByteArray()
	keep.resize(all_list.size())
	for i in limit:
		keep[order[i]] = 1
	var kept_all: Array = []
	var kept_melee: Array = []
	var kept_ranged: Array = []
	for i in all_list.size():
		var enemy := all_list[i] as Enemy
		if keep[i] == 1:
			enemy._ai_tactical = true
			kept_all.append(enemy)
			if enemy.ai_role == ROLE_MELEE:
				kept_melee.append(enemy)
			else:
				kept_ranged.append(enemy)
			continue
		# 掉出战术层的：清意图 + 关槽位 + 走纯场流（不能用陈旧的"直线可走"判定）
		enemy._ai_tactical = false
		enemy._ai_intent = INTENT_NONE
		enemy._ai_slot_valid = false
		enemy._ai_target_radius = 0.0
		enemy._ai_attack_slot = false
		enemy._ai_role_score = 0.0
		enemy._ai_flow_direct = false
	group["all"] = kept_all
	group["melee"] = kept_melee
	group["ranged"] = kept_ranged


static func _is_candidate(enemy: Enemy) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if enemy.has_meta("network_remote_enemy"):
		return false
	# 直接字段访问（Enemy 有 class_name）：get() 走 Variant 查表，每敌 7 次 × 5Hz 是真实开销
	if enemy.ai_role == ROLE_NONE:
		return false
	if enemy.faction == Faction.PLAYER_SIDE:
		return false
	if enemy.route_target != null or enemy.aggro_override != null:
		return false
	if enemy.is_idle != 0 or enemy.frozen:
		return false
	if enemy.is_standby():
		return false
	return true


static func _resolve_target(enemy: Enemy) -> Node2D:
	var target = enemy.get_target()
	if target == null or not is_instance_valid(target) or not (target is Node2D):
		return null
	if not _is_player_node(target):
		return null
	return target as Node2D


static func _is_player_node(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not (node is Node):
		return false
	return node.is_in_group("Player") or node.is_in_group("RemotePlayer")


static func _first_profile(list: Array) -> EnemyAIProfile:
	for enemy in list:
		var profile = enemy.get("ai_profile")
		if profile != null:
			return profile
	return null


static func _group_lead(group: Dictionary) -> float:
	var profile := _first_profile(group.get("all", []))
	if profile == null:
		return 0.0
	return profile.predict_lead_seconds


# ---------------- 密度场 ----------------

static func _cell_of(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / DENSITY_CELL), floori(position.y / DENSITY_CELL))


# 密度格中心（公开：调试可视化要按格画方块）
static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * DENSITY_CELL, (float(cell.y) + 0.5) * DENSITY_CELL)


static func _build_density() -> void:
	_density.clear()
	for enemy in _candidates:
		var base := _cell_of(enemy.global_position)
		_density[base] = float(_density.get(base, 0.0)) + 1.0
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var cell: Vector2i = base + offset
			_density[cell] = float(_density.get(cell, 0.0)) + 0.45
		for offset in [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
			var cell: Vector2i = base + offset
			_density[cell] = float(_density.get(cell, 0.0)) + 0.2


# 自身 splat 到某个邻格上的份额（采样时要扣掉，否则单独一只也会被自己推开）
static func _self_kernel(offset: Vector2i) -> float:
	var manhattan := absi(offset.x) + absi(offset.y)
	if manhattan == 1:
		return 0.45
	if manhattan == 2:
		return 0.2
	return 0.0


# 拥挤度推力：只横散，永不对抗接近。
# ① 背离目标的分量直接丢弃（DENSITY_BACKPRESSURE=0），否则整群会被"推得散开但不接近"；
# ② 幅度按拥挤度软饱和，不再是"有邻居就满强度"，避免稀疏时把方向拧偏。
static func _apply_density_push() -> void:
	var neighbors := [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	for i in _candidates.size():
		var enemy := _candidates[i]
		var position: Vector2 = _ctx_pos[i]
		var self_cell := _cell_of(position)
		enemy._ai_density_level = float(_density.get(self_cell, 0.0))
		var acc := Vector2.ZERO
		for offset in neighbors:
			var cell: Vector2i = self_cell + offset
			var value: float = float(_density.get(cell, 0.0)) - _self_kernel(offset)
			if value <= 0.0:
				continue
			var delta := position - cell_center(cell)
			var distance := delta.length()
			if distance <= 0.01 or distance > DENSITY_FALLOFF:
				continue
			acc += (delta / distance) * value * (1.0 - distance / DENSITY_FALLOFF)
		if acc.length_squared() < 0.0001:
			enemy._ai_density_push = Vector2.ZERO
			continue
		var target := _resolve_target(enemy)
		var toward := Vector2.ZERO
		if target != null:
			var toward_vec := target.global_position - position
			if toward_vec.length_squared() > 0.0001:
				toward = toward_vec.normalized()
		var push: Vector2 = acc
		if toward != Vector2.ZERO:
			var radial := acc.dot(toward)
			push = (acc - toward * radial) + toward * maxf(radial, 0.0) * DENSITY_BACKPRESSURE
		if push.length_squared() < 0.0001:
			enemy._ai_density_push = Vector2.ZERO
			continue
		var magnitude := clampf(push.length() / DENSITY_MAG_REF, 0.0, 1.0)
		enemy._ai_density_push = push.normalized() * magnitude


# 离墙力：把贴墙的敌人持续推离墙面。
# 注意：8 方向探针在「完全被包围」时会正负抵消，所以先判自身格是否 solid——
# 出界 / 卡在障碍格里的敌人必须直接朝最近的可行走点走，否则永远出不来。
static func _apply_wall_push() -> void:
	var directions: Array[Vector2] = []
	for i in 8:
		directions.append(Vector2.from_angle(TAU * float(i) / 8.0))
	for i in _candidates.size():
		var enemy := _candidates[i]
		var position: Vector2 = _ctx_pos[i]
		# 快速放行：离墙远、且所在格 8 邻域没有阻挡格 → 不可能有墙在探针距离内，直接跳过 8 次探针
		# （这是全程最贵的一项：89 只 × 8~16 次 is_solid）
		var cell := MapChunks.world_to_cell(position)
		var cell_index := EnemyNavField.cell_index(cell)
		if EnemyNavField.cell_clearance(cell_index) > WALL_PROBE_FAR + EnemyNavField.CELL_SPAN \
				and not EnemyNavField.cell_near_solid(cell_index):
			enemy._ai_wall_push = Vector2.ZERO
			continue
		if cell_index < 0 or EnemyNavField.is_cell_solid(cell):
			var escape: Vector2 = MapBounds.nearest_inside(position, SLOT_WALL_MARGIN) - position
			if escape.length_squared() > 0.0001:
				enemy._ai_wall_push = escape.normalized()
			else:
				enemy._ai_wall_push = Vector2.ZERO
			continue
		var acc := Vector2.ZERO
		for dir in directions:
			if EnemyNavField.is_solid(position + dir * WALL_PROBE_NEAR):
				acc -= dir
			elif EnemyNavField.is_solid(position + dir * WALL_PROBE_FAR):
				acc -= dir * 0.35
		if acc.length_squared() > 0.0001:
			enemy._ai_wall_push = acc.normalized()
		else:
			enemy._ai_wall_push = Vector2.ZERO


# ---------------- 视线 / 脱困 ----------------

static func _has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	if not EnemyNavField.is_ready():
		return true
	var total := from.distance_to(to)
	if total <= LOS_SKIP * 2.0:
		return true
	var travelled := LOS_SKIP
	var limit := total - LOS_SKIP
	while travelled < limit:
		if EnemyNavField.is_solid(from.lerp(to, travelled / total)):
			return false
		travelled += LOS_STEP
	return true


static func _update_stuck() -> void:
	for i in _candidates.size():
		var enemy := _candidates[i]
		var position: Vector2 = _ctx_pos[i]
		if enemy._ai_stuck_anchor == Vector2.ZERO:
			enemy._ai_stuck_anchor = position
			enemy._ai_stuck_count = 0
			continue
		var moved := position.distance_to(enemy._ai_stuck_anchor)
		if moved < STUCK_EPSILON:
			var count: int = enemy._ai_stuck_count + 1
			enemy._ai_stuck_count = count
			if count >= STUCK_SOLVES:
				enemy._ai_unstuck_ticks = UNSTUCK_TICKS
				enemy._ai_stuck_count = 0
		else:
			enemy._ai_stuck_count = 0
		enemy._ai_stuck_anchor = position


# ---------------- 槽位公用 ----------------

static func _mean_bearing(list: Array, anchor: Vector2) -> float:
	var sum := Vector2.ZERO
	for enemy in list:
		var delta: Vector2 = enemy.global_position - anchor
		if delta.length_squared() < 0.0001:
			continue
		sum += delta.normalized()
	if sum.length_squared() < 0.0004:
		return NAN
	return sum.angle()


static func _bearing_of(position: Vector2, anchor: Vector2) -> float:
	var delta := position - anchor
	if delta.length_squared() < 0.0001:
		return 0.0
	return delta.angle()


static var slot_ok_calls: int = 0


# 排序：先把 key 算一次，再只比 key。
# 原来的比较器里现算 distance_squared / atan2 / 查字典，89 人 × 5 个排序 ≈ 2800 次昂贵比较，实测是 solve 的最大单项。
static func _ordered_by(items: Array, keys: PackedFloat32Array, descending: bool) -> Array:
	var order := _sorted_indices(keys, descending)
	var n := items.size()
	var out: Array = []
	out.resize(n)
	for i in n:
		out[i] = items[order[i]]
	return out


# 纯 GDScript 自底向上归并排序：比较只是一次数组读，不走 Callable 分发
# （sort_custom 每次比较约 0.5~1µs，89 元素 × 5 个排序就要 ~2ms）
static func _sorted_indices(keys: PackedFloat32Array, descending: bool) -> PackedInt32Array:
	var n := keys.size()
	var src := PackedInt32Array()
	src.resize(n)
	for i in n:
		src[i] = i
	if n <= 1:
		return src
	var dst := PackedInt32Array()
	dst.resize(n)
	var width := 1
	while width < n:
		var i := 0
		while i < n:
			var mid := mini(i + width, n)
			var end := mini(i + width * 2, n)
			var a := i
			var b := mid
			var k := i
			while a < mid and b < end:
				var take_a: bool
				if descending:
					take_a = keys[src[a]] >= keys[src[b]]
				else:
					take_a = keys[src[a]] <= keys[src[b]]
				if take_a:
					dst[k] = src[a]
					a += 1
				else:
					dst[k] = src[b]
					b += 1
				k += 1
			while a < mid:
				dst[k] = src[a]
				a += 1
				k += 1
			while b < end:
				dst[k] = src[b]
				b += 1
				k += 1
			i = end
		var swap := src
		src = dst
		dst = swap
		width *= 2
	return src


# 一批方位角 key（每敌只算一次 atan2）
static func _bearing_keys(items: Array, anchor: Vector2) -> PackedFloat32Array:
	var keys := PackedFloat32Array()
	keys.resize(items.size())
	for i in items.size():
		keys[i] = _bearing_of(items[i].global_position, anchor)
	return keys


# 槽点是否可站：可行走区（含离墙余量）+ 非阻挡 + 相对目标可达。
# 只换一次格；离墙余量先用预计算表判定，只有"模糊带"才真的做 polygon 判定（原来每次都判）。
static func _slot_ok(point: Vector2, target: Node2D) -> bool:
	slot_ok_calls += 1
	var cell := MapChunks.world_to_cell(point)
	var index := EnemyNavField.cell_index(cell)
	if index < 0:
		return false
	var margin := EnemyNavField.cell_clearance(index)
	var span := EnemyNavField.CELL_SPAN
	if margin + span < SLOT_WALL_MARGIN:
		return false
	if margin < SLOT_WALL_MARGIN + span:
		if MapBounds.nearest_inside(point, SLOT_WALL_MARGIN) != point:
			return false
	if EnemyNavField.is_cell_solid(cell):
		return false
	var d := EnemyNavField.cell_dist(index, target)
	if d >= 0.0 and d == INF:
		return false
	return true


# 把 (角度, 半径) 收缩/外扩到可站立的位置。
# 先试原半径；不行先向内收缩（到 min_radius）；仍不行再向外增长（到 max_radius，<0 表示不允许）。
# 返回可用半径；都失败返回 -1（该敌人本帧不下发槽位）。
static func _fit_slot(target: Node2D, anchor: Vector2, angle: float, radius: float,
		min_radius: float, max_radius: float = -1.0) -> float:
	if _slot_ok(anchor + Vector2.from_angle(angle) * radius, target):
		return radius
	var r: float = radius
	for step in SLOT_SHRINK_MAX_STEPS:
		r *= SLOT_SHRINK_RATIO
		if r < min_radius:
			break
		if _slot_ok(anchor + Vector2.from_angle(angle) * r, target):
			return r
	if max_radius > radius:
		r = radius
		for step in SLOT_GROW_MAX_STEPS:
			r *= SLOT_GROW_RATIO
			if r > max_radius:
				break
			if _slot_ok(anchor + Vector2.from_angle(angle) * r, target):
				return r
	return -1.0


# 最长连续可站立弧：环带角度只铺在这段弧里，避免把人派进墙。
# 返回 {"start": 弧度, "span": 弧度}；可达性好时退化为整圈。
static func _free_arc(target: Node2D, anchor: Vector2, radius: float) -> Dictionary:
	var ok: Array[bool] = []
	var valid := 0
	for i in ARC_SAMPLES:
		var angle := TAU * float(i) / float(ARC_SAMPLES)
		var good: bool = _slot_ok(anchor + Vector2.from_angle(angle) * radius, target)
		ok.append(good)
		if good:
			valid += 1
	if valid == 0:
		return {"start": 0.0, "span": TAU}
	if valid >= ARC_SAMPLES:
		return {"start": 0.0, "span": TAU}
	# 环形数组里找最长连续 true
	var best_start := 0
	var best_len := 0
	var run_start := -1
	var run_len := 0
	for i in ARC_SAMPLES * 2:
		var index := i % ARC_SAMPLES
		if ok[index]:
			if run_start < 0:
				run_start = i
				run_len = 0
			run_len += 1
			if run_len > best_len:
				best_len = run_len
				best_start = run_start
		else:
			run_start = -1
			run_len = 0
	if best_len <= 0:
		return {"start": 0.0, "span": TAU}
	var step := TAU / float(ARC_SAMPLES)
	var start := TAU * float(best_start % ARC_SAMPLES) / float(ARC_SAMPLES)
	var span: float = minf(TAU, step * float(best_len))
	return {"start": start, "span": span}


static func _invalidate_slot(enemy: Node) -> void:
	enemy.set("_ai_slot_valid", false)
	enemy.set("_ai_target_radius", 0.0)


static func _apply_slot(enemy, angle: float, radius: float, intent: int) -> void:
	# 直接字段访问（Enemy 有 class_name）：get/set 走 Variant 查表，每次 ~0.5µs，
	# 每人 8 次 × 89 人就吃掉 ~0.35ms
	var e := enemy as Enemy
	if e == null:
		return
	var was_valid: bool = e._ai_slot_valid
	var smoothed_angle: float = angle
	var smoothed_radius: float = radius
	if was_valid:
		smoothed_angle = lerp_angle(e._ai_slot_angle, angle, SLOT_SMOOTH)
		if e._ai_target_radius > 0.0:
			# 只允许"向半径小的方向平滑"：收缩必须立刻到位，否则平滑出来的中间半径可能已经在墙外
			smoothed_radius = minf(lerpf(e._ai_target_radius, radius, SLOT_SMOOTH), radius)
	e._ai_slot_angle = smoothed_angle
	e._ai_slot_valid = true
	e._ai_target_radius = smoothed_radius
	e._ai_intent = intent


# ---------------- 角色评分（位置 + 速度） ----------------

# 敌人当前实际速度（move_and_slide 之后），拿不到就返回 ZERO。
static func _enemy_velocity(enemy) -> Vector2:
	if enemy == null or not is_instance_valid(enemy):
		return Vector2.ZERO
	var raw = enemy.get("velocity")
	if raw is Vector2:
		return raw
	return Vector2.ZERO


# 前插分：能不能最快堵到预判落点（ETA）+ 是否在玩家前进方向上。
static func _score_intercept(enemy, anchor: Vector2, intercept_anchor: Vector2,
		player_head: float) -> float:
	var position: Vector2 = enemy.global_position
	var to_ip := intercept_anchor - position
	var dist_ip := to_ip.length()
	var approach := 40.0
	if dist_ip > 0.01:
		approach = maxf(40.0, _enemy_velocity(enemy).dot(to_ip / dist_ip))
	var eta := dist_ip / approach
	var eta_norm := 1.0 / (1.0 + eta / ETA_REF)
	var ahead := 0.5
	if not is_nan(player_head):
		ahead = 0.5 + 0.5 * cos(angle_difference(player_head, (position - anchor).angle()))
	var score := 0.55 * eta_norm + 0.45 * ahead
	if int(enemy.get("_ai_intent")) == INTENT_CUTOFF:
		score += ROLE_HYSTERESIS
	return score


# 前排分：是否已经够近 + 是否正在朝玩家收拢。
static func _score_front(enemy, anchor: Vector2, ring_radius: float) -> float:
	var position: Vector2 = enemy.global_position
	var to_anchor := anchor - position
	var distance := to_anchor.length()
	# 平滑衰减而不是硬截断：远距离之间也要保持"越近越优先"的次序
	var proximity := 1.0 / (1.0 + distance / maxf(1.0, ring_radius))
	var closing := 0.0
	if distance > 0.01:
		closing = _enemy_velocity(enemy).dot(to_anchor / distance)
	var closing_norm := clampf(closing / CLOSING_REF, 0.0, 1.0)
	var score := 0.6 * proximity + 0.4 * closing_norm
	if int(enemy.get("_ai_intent")) == INTENT_CHASE:
		score += ROLE_HYSTERESIS
	return score


# ---------------- 场流兜底 ----------------

# 等距瓦片的 4 邻接 BFS 只能给出 (±0.894, ±0.447) 四个对角方向，正上/正下必然逐格翻面。
# 这里在「当前点」和「沿目标方向 26px 的下一点」各采一次，锯齿处两点反向 → 相加只剩前向；
# 两次采样几乎抵消（真正的锯齿）时直接退回直线目标。
static func _smooth_field_flow(pos: Vector2, target: Node2D, toward: Vector2) -> Vector2:
	var a := EnemyNavField.sample(pos, target)
	if a == Vector2.ZERO:
		return Vector2.ZERO
	if toward == Vector2.ZERO:
		return a
	var b := EnemyNavField.sample(pos + toward * FLOW_LOOKAHEAD, target)
	if b == Vector2.ZERO:
		return a
	var mixed := a + b
	if mixed.length() < 0.15:
		return toward
	return mixed.normalized()


# ---------------- 近战：包围 + 封堵 ----------------

static func _assign_melee_slots(group: Dictionary, anchor: Vector2) -> void:
	var melee: Array = group.get("melee", [])
	var count := melee.size()
	if count <= 0:
		return
	var profile := _first_profile(melee)
	if profile == null:
		return
	var node = group.get("node")
	if node == null or not is_instance_valid(node):
		return

	# 直线可走就别用场流：等距格流只有 4 个对角方向，正上/正下会逐格翻面（左右摇摆）
	# 视线很贵（每 24px 一次 is_solid）；地形不动，双方位移 <24px 时直接沿用上次结果
	for enemy in melee:
		var los_pos: Vector2 = enemy.global_position
		var le := enemy as Enemy
		if le != null and le._ai_los_pos != Vector2.ZERO \
				and le._ai_los_pos.distance_squared_to(los_pos) < 576.0 \
				and le._ai_los_anchor.distance_squared_to(anchor) < 576.0:
			continue
		enemy.set("_ai_flow_direct", _has_line_of_sight(los_pos, anchor))
		enemy.set("_ai_los_pos", los_pos)
		enemy.set("_ai_los_anchor", anchor)

	# 1) 距离名次（越靠前越近）：可及性差的敌人不占位
	var dist_keys := PackedFloat32Array()
	dist_keys.resize(count)
	for i in count:
		dist_keys[i] = melee[i].global_position.distance_squared_to(anchor)
	var by_dist := _ordered_by(melee, dist_keys, false)
	var dist_rank: Dictionary = {}
	for rank in count:
		dist_rank[by_dist[rank].get_instance_id()] = rank

	# 2) 环基准角
	var mean := _mean_bearing(by_dist, anchor)
	var base: float = mean
	if is_nan(mean):
		base = float(group.get("base", 0.0))
	elif group.has("base"):
		base = lerp_angle(float(group["base"]), mean, BASE_SMOOTH)
	var velocity := target_velocity(node)
	if profile.flank_bias > 0.0 and velocity != Vector2.ZERO:
		base = lerp_angle(base, (-velocity).angle(), clampf(profile.flank_bias, 0.0, 1.0))
	group["base"] = base

	# 3) 名额：前排（attack_slots 派生）/ 前插（intercept_ratio 派生）/ 环带（剩余）
	var attack_count := clampi(profile.attack_slots + int((count - 1) / 4.0), 1, 6)
	attack_count = mini(attack_count, count)
	var intercept_count := 0
	if profile.intercept_ratio > 0.0 and count > 1:
		intercept_count = clampi(roundi(float(count) * profile.intercept_ratio),
			maxi(0, profile.cutoff_slots), maxi(0, profile.cutoff_max))
		intercept_count = clampi(intercept_count, 0, count - 1)
	# 三层保底：人多时保证「前排 / 环带 / 前插」各至少 1 个，否则"完全体"看不出分层。
	# 注意 attack_slots 只管前排（贴脸压迫）名额，围堵人数由 intercept_* 决定。
	if count >= 6 and intercept_count > 0:
		intercept_count = mini(intercept_count, count - 2)
		attack_count = mini(attack_count, count - 1 - intercept_count)
	attack_count = maxi(attack_count, 1)

	# 4) 前插方向：沿玩家速度；玩家静止时沿用上次方向
	var cut_dir: float = float(group.get("cut_dir", base))
	if velocity != Vector2.ZERO:
		cut_dir = velocity.angle()
		group["cut_dir"] = cut_dir
	var half := deg_to_rad(clampf(profile.cutoff_spread_deg, 10.0, 120.0)) * 0.5

	# 5) 前插组：围绕「预判落点」站位（不是玩家当前位置）。人数按比例分配，至少留 1 个压迫。
	#    选人用「ETA + 朝向」评分：离得近但被卡住（速度≈0）的敌人不该抢走名额。
	var intercept_anchor: Vector2 = anchor
	if profile.cutoff_speed_lead > 0.0:
		intercept_anchor = predict_anchor(node, profile.cutoff_speed_lead)
	var player_head: float = NAN
	if velocity != Vector2.ZERO:
		player_head = velocity.angle()
	else:
		player_head = cut_dir
	var cutoff_list: Array = []
	if intercept_count > 0:
		var cut_keys := PackedFloat32Array()
		cut_keys.resize(count)
		var score_of: Dictionary = {}
		for i in count:
			cut_keys[i] = _score_intercept(melee[i], anchor, intercept_anchor, player_head)
			score_of[melee[i].get_instance_id()] = cut_keys[i]
		var scored := _ordered_by(melee, cut_keys, true)
		for i in mini(intercept_count, scored.size()):
			cutoff_list.append(scored[i])
			scored[i].set("_ai_role_score", float(score_of[scored[i].get_instance_id()]))

	# 6) 前插槽：先按方位角排序，再按同序铺进前扇形（顺序保持 → 不会横穿整群）
	cutoff_list = _ordered_by(cutoff_list, _bearing_keys(cutoff_list, intercept_anchor), false)
	for i in cutoff_list.size():
		var t: float = 0.0 if cutoff_list.size() == 1 else (float(i) / float(cutoff_list.size() - 1))
		var angle: float = cut_dir + lerpf(-half * 0.9, half * 0.9, t)
		var fitted: float = _fit_slot(node, intercept_anchor, angle,
			profile.cutoff_distance, profile.melee_engage_radius, profile.cutoff_distance * 1.6)
		if fitted < 0.0:
			fitted = _fit_slot(node, intercept_anchor, angle, profile.melee_ring_radius,
				profile.melee_engage_radius, SLOT_MAX_RADIUS)
		if fitted < 0.0:
			_invalidate_slot(cutoff_list[i])
		else:
			_apply_slot(cutoff_list[i], angle, fitted, INTENT_CUTOFF)
			cutoff_list[i].set("_ai_anchor", intercept_anchor)

	# 7) 压迫组拆成「前排 + 同心环」
	var press_list: Array = []
	for enemy in melee:
		if cutoff_list.has(enemy):
			continue
		press_list.append(enemy)
	# 前排 = 前排分（近 + 正在收拢）最高的 attack_count 个；其余按距离升序占内圈
	# 只取前 k 名，用「有序插入的小数组」选择，不做 89 元素的整表排序
	var front_count0 := mini(attack_count, press_list.size())
	var front_best: Array = []
	var front_best_keys := PackedFloat32Array()
	var front_score_of: Dictionary = {}
	for i in press_list.size():
		var enemy = press_list[i]
		var score := _score_front(enemy, anchor, profile.melee_ring_radius)
		front_score_of[enemy.get_instance_id()] = score
		if front_best.size() < front_count0:
			var at := front_best.size()
			while at > 0 and front_best_keys[at - 1] < score:
				at -= 1
			front_best.insert(at, enemy)
			front_best_keys.insert(at, score)
		elif front_best.size() > 0 and score > front_best_keys[front_best.size() - 1]:
			var at := front_best.size() - 1
			while at > 0 and front_best_keys[at - 1] < score:
				at -= 1
			front_best.insert(at, enemy)
			front_best_keys.insert(at, score)
			front_best.remove_at(front_best.size() - 1)
			front_best_keys.remove_at(front_best_keys.size() - 1)
	var front_count := front_best.size()
	var front: Array = front_best
	for i in front_count:
		front[i].set("_ai_role_score", float(front_score_of[front[i].get_instance_id()]))
	# 环带按距离升序占内圈：直接复用已按距离排好的 by_dist（不再单独排一次）
	var chosen: Dictionary = {}
	for e in front:
		chosen[e.get_instance_id()] = true
	for e in cutoff_list:
		chosen[e.get_instance_id()] = true
	var ring_pool: Array = []
	for e in by_dist:
		if not chosen.has(e.get_instance_id()):
			ring_pool.append(e)

	# 7a) 前排：按方位角排序后均分整圈扇区，径向恒 +1（真正贴脸）
	front = _ordered_by(front, _bearing_keys(front, anchor), false)
	for i in front_count:
		var angle: float = base + TAU * float(i) / maxf(1.0, float(front_count))
		var front_radius: float = profile.melee_engage_radius
		var fitted: float = _fit_slot(node, anchor, angle, front_radius, 0.0)
		_apply_slot(front[i], angle, fitted if fitted > 0.0 else front_radius, INTENT_CHASE)
		front[i].set("_ai_anchor", anchor)

	# 7b) 同心环：角度只铺在「最长连续可站立弧」内；环内按方位角同序铺满。
	#     玩家在角落/墙边时可站弧变窄，半径随圈数外扩，形成扇形包围而不是挤成一条线。
	var ring_base: float = maxf(profile.melee_ring_radius, profile.melee_engage_radius * 1.6)
	var arc := _free_arc(node, anchor, ring_base)
	var arc_start: float = float(arc["start"])
	var arc_span: float = float(arc["span"])
	group["arc_start"] = arc_start
	group["arc_span"] = arc_span
	group["arc_radius"] = ring_base
	var remaining: Array = ring_pool
	var ring_index := 0
	while not remaining.is_empty() and ring_index < 10:
		var radius: float = (ring_base + RING_SPACING * float(ring_index)) * _jitter_of(remaining[0], 0.2)
		var capacity: int = maxi(1, int(arc_span * radius / RING_SLOT_SIZE))
		var take: int = mini(capacity, remaining.size())
		var members: Array = remaining.slice(0, take)
		remaining = remaining.slice(take)
		members = _ordered_by(members, _bearing_keys(members, anchor), false)
		for j in take:
			var angle: float = arc_start + arc_span * (float(j) + 0.5) / float(take)
			var fitted: float = _fit_slot(node, anchor, angle, radius,
				profile.melee_engage_radius, SLOT_MAX_RADIUS)
			if fitted < 0.0:
				_invalidate_slot(members[j])
			else:
				_apply_slot(members[j], angle, fitted, INTENT_RING)
				members[j].set("_ai_anchor", anchor)
		ring_index += 1

	# 8) 名次与攻击位标记（只影响切向权重，不改意图）。前排=贴脸名额。
	var front_set: Dictionary = {}
	for enemy in front:
		front_set[enemy] = true
	var cut_set: Dictionary = {}
	for enemy in cutoff_list:
		cut_set[enemy] = true
	for enemy in melee:
		var e := enemy as Enemy
		if e == null:
			continue
		e._ai_dist_rank = int(dist_rank.get(enemy.get_instance_id(), 0))
		e._ai_attack_slot = front_set.has(enemy)
		if not e._ai_attack_slot and not cut_set.has(enemy):
			e._ai_role_score = 0.0

	_assign_queue_push(melee, anchor, dist_rank)


# ---------------- 远程：错落站位 + 视线换位 ----------------

static func _assign_ranged_slots(group: Dictionary, anchor: Vector2) -> void:
	var ranged: Array = group.get("ranged", [])
	var count := ranged.size()
	if count <= 0:
		return
	var profile := _first_profile(ranged)
	if profile == null:
		return
	var node = group.get("node")
	if node == null or not is_instance_valid(node):
		return
	var base := _mean_bearing(ranged, anchor)
	if is_nan(base):
		base = float(group.get("base", 0.0))
	for enemy in ranged:
		var los_pos: Vector2 = enemy.global_position
		var last_pos = enemy.get("_ai_los_pos")
		var last_anchor = enemy.get("_ai_los_anchor")
		if last_pos is Vector2 and last_anchor is Vector2 \
				and (last_pos as Vector2).distance_squared_to(los_pos) < 576.0 \
				and (last_anchor as Vector2).distance_squared_to(anchor) < 576.0:
			continue
		enemy.set("_ai_flow_direct", _has_line_of_sight(los_pos, anchor))
		enemy.set("_ai_los_pos", los_pos)
		enemy.set("_ai_los_anchor", anchor)
	var player_velocity := target_velocity(node)
	var slots := clampi(count, 1, MAX_SLOTS)
	for i in count:
		var enemy = ranged[i]
		var position: Vector2 = enemy.global_position
		var shoot := _num_of(enemy.get("shoot_range"), 320.0)
		var back := _num_of(enemy.get("back_range"), 24.0)
		if shoot <= 0.0:
			shoot = 320.0
		var ratio: float = clampf(profile.ranged_standoff_ratio, 0.2, 1.0)
		var jitter := _jitter_of(enemy, 0.15)
		var standoff: float = lerpf(back, shoot, ratio) * jitter
		standoff = clampf(standoff, back + 12.0, shoot * 0.95)
		var slot_index := i % slots
		var tier := int(i / slots)
		var angle: float = base + TAU * float(slot_index) / float(slots)
		var distance := position.distance_to(anchor)
		var intent := INTENT_HOLD
		# 玩家高速朝自己冲来时提前后撤，而不是等贴到 back_range 才反应
		var closing := 0.0
		if distance > 0.01 and player_velocity != Vector2.ZERO:
			closing = player_velocity.dot((position - anchor) / distance)
		var danger_range: float = minf(shoot, standoff * 1.1)
		if distance > shoot:
			intent = INTENT_CHASE
		elif distance < back or (closing > RANGED_DANGER_SPEED and distance < danger_range):
			intent = INTENT_KITE
		else:
			var has_los := _has_line_of_sight(position, anchor)
			enemy.set("_ai_has_los", has_los)
			if not has_los:
				var side: float = float(enemy.get("_ai_strafe_sign"))
				if side == 0.0:
					side = 1.0
				angle += deg_to_rad(50.0) * side
				intent = INTENT_REPOS
		var wanted: float = standoff * (1.0 + 0.12 * float(tier))
		enemy.set("_ai_dist_rank", i)  # 远程只用于调试标签，取槽位序号即可
		var fitted: float = _fit_slot(node, anchor, angle, wanted, back + 12.0)
		if fitted < 0.0:
			_invalidate_slot(enemy)
		else:
			_apply_slot(enemy, angle, fitted, intent)
			enemy.set("_ai_anchor", anchor)


static func _num_of(value, fallback: float) -> float:
	if value == null:
		return fallback
	if value is int or value is float:
		return float(value)
	return fallback


static func _jitter_of(enemy: Node, spread: float) -> float:
	var id := enemy.get_instance_id()
	var unit := float(int(id) % 1000) / 1000.0
	return 1.0 - spread * 0.5 + spread * unit


# ---------------- 反排队 ----------------

# 反排队：只处理「正前方有更靠近目标的同类」的情况，沿垂直于目标方向推开。
# 侧向取实例奇偶（稳定，不受名次抖动影响），左右各半 → 队列两两分道而不是整体平移。
static func _assign_queue_push(melee: Array, anchor: Vector2, dist_rank: Dictionary) -> void:
	var count := melee.size()
	if count <= 1:
		return
	# 空间哈希：只与 3×3 邻桶比较（96 > QUEUE_RADIUS 72，覆盖全部候选），避免 O(n²)
	var buckets: Dictionary = {}
	for enemy in melee:
		var p: Vector2 = enemy.global_position
		var key := Vector2i(int(floor(p.x / QUEUE_BUCKET)), int(floor(p.y / QUEUE_BUCKET)))
		var list = buckets.get(key)
		if list == null:
			list = []
			buckets[key] = list
		list.append(enemy)
	for i in count:
		var enemy = melee[i]
		var position: Vector2 = enemy.global_position
		var to_target := anchor - position
		var distance := to_target.length()
		if distance < 0.001:
			enemy.set("_ai_queue_push", Vector2.ZERO)
			continue
		var dir_to_target := to_target / distance
		var lateral := dir_to_target.orthogonal()
		var side = enemy.get("_ai_fan_side")
		if side == null or float(side) == 0.0:
			var rank: int = int(dist_rank.get(enemy.get_instance_id(), i))
			side = 1.0 if rank % 2 == 0 else -1.0
		var own_dist_sq := distance * distance
		var push := Vector2.ZERO
		var pressure := 0.0
		var base_key := Vector2i(int(floor(position.x / QUEUE_BUCKET)),
			int(floor(position.y / QUEUE_BUCKET)))
		for dx in 3:
			for dy in 3:
				var list = buckets.get(base_key + Vector2i(dx - 1, dy - 1))
				if list == null:
					continue
				for other in list:
					if other == enemy:
						continue
					var other_position: Vector2 = other.global_position
					# 只处理「比我更靠近目标」的同类（真的在我前面）
					if other_position.distance_squared_to(anchor) >= own_dist_sq:
						continue
					var offset := other_position - position
					var gap := offset.length()
					if gap <= 0.01 or gap > QUEUE_RADIUS:
						continue
					if offset.dot(dir_to_target) / gap < QUEUE_COS:
						continue
					var weight := 1.0 - gap / QUEUE_RADIUS
					push += lateral * float(side) * weight
					pressure += weight
		if push.length_squared() > 0.0001:
			push = push.normalized()
		var qe := enemy as Enemy
		if qe != null:
			qe._ai_queue_push = push
			# 队列纪律：正前方被堵得越实，环带越不该继续死推（形成有间距的队列而不是挤压）
			qe._ai_queue_pressure = clampf(pressure, 0.0, 1.0)
		else:
			enemy.set("_ai_queue_push", push)
			enemy.set("_ai_queue_pressure", clampf(pressure, 0.0, 1.0))
