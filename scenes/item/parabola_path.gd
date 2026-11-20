extends Node2D

## 硬币抛掷（旧名 `parabola_path`，2026-11-20 由 Path2D + Curve2D + Tween 重做为
## 抛壳式代码弹道；保留文件名/UID/池 id 以免断掉 mod 与测试的引用）。
##
## 池契约（沿用旧版，勿改）：本节点走 `parabola_coins` 池、金币 body 走 `coins` 池；
## `drop()` 取 body、`coin.idled` 触发 `_release_body()` 把金币摘回 `CoinRoot` 并补
## `add_pool("coins")`，最后本节点才置 `is_idle=1`。
##
## 关键约定（用户 2026-11-20 敲定）：
## - **从地面抛出**：起点离地高度恒为 0（不接枪口高度），`height` 只用于渲染偏移；
## - **随机落点**：每枚独立采样角度 + 距离，被地图外边界推走的候选重新采样；
## - **必然落在可行走区**：`MapBounds.nearest_inside` 压回外边界，再排除壁垒
##   `NavObstacle` 内部墙（`EnemyNavField.is_solid/is_body_safe`），兜底
##   `EnemyNavField.safe_pickup_point()`；
## - **弧顶高于弹壳**：默认 `arc_height=96`（弹壳弧顶只有 18.8~40.1px）；
## - 首次触地水平速度清零 → 静止点严格等于选中的落点，不会滑进墙里。

const COIN_SCENE: PackedScene = preload("res://scenes/item/coin.tscn")
const PATH_POOL_ID: String = "parabola_coins"
const COIN_POOL_ID: String = "coins"
const COIN_LAYER: int = 64
## 外边界把候选推走超过该距离就重新采样，避免一排金币贴着墙。
const LANDING_SNAP_TOLERANCE: float = 2.0
## 联机折线广播的采样步长（1/30s 足够平滑，且把可靠包压到几十个点）。
const TRAJECTORY_DT: float = 1.0 / 30.0

## 每个物理帧只探一次「有没有壁垒墙 + 拓扑是否可用」：coin_box 同帧补发 100 枚时
## 不必重复扫 NavObstacle 组 / 重算拓扑签名。
static var _walls_probe_frame: int = -1
static var _walls_probe_ok: bool = false

@export var coin_num: int = 1
@export var min_drop_distance: float = 30.0
@export var max_drop_distance: float = 120.0
# -1 = coin_box 的 0~PI 随机角度；>=0 时作为基准角度（可配合抖动）
@export var angle_override: float = -1.0
@export var clamp_to_walkable: bool = true
@export var map_clearance: float = 16.0
@export var ignore_coin_mult: bool = false
@export var ignore_auto_pick: bool = false
@export var personal_pickup: bool = false
@export var play_drop_sound: bool = true
## 弧顶高度（px），必须明显高于弹壳（18.8~40.1px）。
@export var arc_height: float = 96.0
## 抛出 → 首次落地的时长（秒）。后续还有 bounce_budget 次小弹跳。
@export var fall_duration: float = 0.95
@export var bounce_budget: int = 2
@export var target_attempts: int = 8

var is_idle: int = 1
var body: Area2D = null

var _state: Dictionary = {}
var _trajectory: Dictionary = {}
var _walls: bool = false
var _releasing: bool = false
var _body_layer: int = COIN_LAYER

func _ready() -> void:
	PoolManager.add_pool(PATH_POOL_ID, self)
	set_physics_process(false)

## 从本节点所在的地面位置抛出。origin_offset 为地面偏移（旧调用一律传 ZERO）。
func drop(origin_offset: Vector2 = Vector2.ZERO) -> void:
	if is_idle == 0:
		return
	if body != null:
		return
	is_idle = 0
	_releasing = false
	_trajectory = {}
	visible = true
	var origin: Vector2 = global_position + origin_offset
	# nearest_inside 不会自己保证边界已建好；每个 burst 只做一次 O(1) 检查（已建好时）。
	MapBounds.ensure_ready()
	_walls = _walls_available()
	var target: Vector2 = _pick_landing(origin)
	# 必须先有弹道状态再 active_state()：联机 mod 在 on_coin_spawned 里同步读 get_trajectory()。
	_state = CoinBallistic.launch(origin, target, arc_height, fall_duration, bounce_budget)
	body = _acquire_body()
	if body == null:
		is_idle = 1
		_state = {}
		visible = false
		return
	body.coin = coin_num
	body.pick_up = false
	body.target = null
	body.can_pick = false
	body.ignore_coin_mult = ignore_coin_mult
	body.ignore_auto_pick = ignore_auto_pick
	body.personal_pickup = personal_pickup
	_body_layer = body.collision_layer if body.collision_layer != 0 else COIN_LAYER
	# 金币出生点就是玩家位置，会立刻与 PickBox 重叠；惩罚金币在飞行期间
	# 先退出拾取层，否则 PickBox 会在出生帧把 pick_up 置真，静止后自动飞回。
	var suppress_pickbox: bool = body.ignore_auto_pick
	if suppress_pickbox:
		body.collision_layer = 0
	body.idled.connect(_on_body_idled, CONNECT_ONE_SHOT)
	global_position = origin
	reset_physics_interpolation()
	body.active_state()
	if play_drop_sound:
		SoundManager.play_sfx("ButtonSounds")
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if is_idle == 1 or body == null:
		set_physics_process(false)
		return
	# 青辉石自动拾取接管：金币自己会磁吸过去，本节点不再驱动位置（避免抢写）。
	if body.pick_up and body.can_pick:
		set_physics_process(false)
		return
	var was_resting: bool = bool(_state.get("resting", false))
	_state = CoinBallistic.step(_state, delta)
	global_position = CoinBallistic.render_position(_state)
	if not was_resting and bool(_state.get("resting", false)):
		_finalize_landing()
		set_physics_process(false)

## 静止：开放拾取，惩罚金币恢复碰撞层并清掉飞行期被 PickBox 置上的 pick_up。
func _finalize_landing() -> void:
	reset_physics_interpolation()
	if body == null or not is_instance_valid(body):
		return
	body.can_pick = true
	if body.ignore_auto_pick:
		body.pick_up = false
		body.target = null
		body.collision_layer = _body_layer

## 联机镜像用：世界坐标折线 + 总时长（首次调用时预演并缓存）。
func get_trajectory() -> Dictionary:
	if not _trajectory.is_empty():
		return _trajectory
	if _state.is_empty():
		return {}
	_trajectory = CoinBallistic.simulate(_state, TRAJECTORY_DT)
	return _trajectory

func idle_state() -> void:
	if is_idle == 1 and body == null:
		return
	if _releasing:
		return
	set_physics_process(false)
	visible = false
	_state = {}
	_trajectory = {}
	if body == null:
		is_idle = 1
		_reset_drop_config()
		return
	if body.is_idle == 0:
		# body.idle_state() 会发 idled，由 _on_body_idled 回收。
		body.idle_state()
	else:
		_releasing = true
		_release_body()

func clear_uncollected() -> void:
	if is_idle == 1 and body == null:
		return
	idle_state()

func _acquire_body() -> Area2D:
	var coin = PoolManager.get_pool_idle(COIN_POOL_ID)
	if coin == null:
		coin = COIN_SCENE.instantiate()
		add_child(coin)
	elif coin.get_parent() != self:
		coin.reparent(self, false)
	coin.position = Vector2.ZERO
	return coin as Area2D

func _on_body_idled() -> void:
	if _releasing:
		return
	_releasing = true
	_release_body()

func _release_body() -> void:
	set_physics_process(false)
	var released := body
	body = null
	if released != null and is_instance_valid(released):
		released.can_pick = false
		released.collision_layer = _body_layer
		var tree := get_tree()
		var root = tree.get_first_node_in_group("CoinRoot") if tree != null else null
		if root != null:
			released.reparent(root, false)
			released.position = Vector2.ZERO
			PoolManager.add_pool(COIN_POOL_ID, released)
		else:
			released.queue_free()
	_releasing = false
	is_idle = 1
	_state = {}
	_trajectory = {}
	visible = false
	_reset_drop_config()

func _reset_drop_config() -> void:
	# 路径池会在 coin_box 与索尼克之间复用；恢复 coin_box 的默认配置，
	# 避免上一次索尼克掉落的 0.7s / ignore_auto_pick / clamp 泄漏到普通金币。
	coin_num = 1
	min_drop_distance = 30.0
	max_drop_distance = 120.0
	angle_override = -1.0
	clamp_to_walkable = true
	map_clearance = 16.0
	ignore_coin_mult = false
	ignore_auto_pick = false
	personal_pickup = false
	play_drop_sound = true
	arc_height = 96.0
	fall_duration = 0.95
	bounce_budget = 2
	target_attempts = 8

# ---------------- 落点：随机 + 外边界 + 壁垒内部墙 ----------------

func _pick_landing(origin: Vector2) -> Vector2:
	var min_dist := maxf(0.0, minf(min_drop_distance, max_drop_distance))
	var max_dist := maxf(min_dist, maxf(min_drop_distance, max_drop_distance))
	var candidate := origin + Vector2.from_angle(_drop_angle()) * randf_range(min_dist, max_dist)
	if not clamp_to_walkable:
		return candidate
	var fallback := origin
	var attempts := maxi(1, target_attempts)
	for _i in attempts:
		candidate = origin + Vector2.from_angle(_drop_angle()) * randf_range(min_dist, max_dist)
		var clamped := MapBounds.nearest_inside(candidate, map_clearance)
		fallback = clamped
		# 被外边界推走 → 重新采样，避免金币沿墙排成一条线。
		if clamped.distance_to(candidate) > LANDING_SNAP_TOLERANCE:
			continue
		if _landing_ok(clamped):
			return clamped
	if _landing_ok(fallback):
		return fallback
	# 兜底：safe_pickup_point 先压外边界再找最近 body-safe 格；没有壁垒时只压外边界。
	var safe := EnemyNavField.safe_pickup_point(fallback) if _walls \
		else MapBounds.nearest_inside(fallback, map_clearance)
	if not safe.is_finite():
		safe = MapBounds.nearest_inside(origin, map_clearance)
	return safe if safe.is_finite() else origin

## 落点是否可站人：无壁垒时只信 MapBounds（外边界已在候选阶段压过）；
## 有壁垒时排除 solid 格，并要求格心离墙余量够（避免金币半个身子嵌进墙砖）。
func _landing_ok(pos: Vector2) -> bool:
	if not _walls:
		return true
	if EnemyNavField.is_solid(pos):
		return false
	return EnemyNavField.is_body_safe(pos, 1)

func _drop_angle() -> float:
	if angle_override < 0.0:
		return randf_range(0.0, PI)
	return angle_override + randf_range(-0.2, 0.2)

## 壁垒内部墙只在 NavObstacle / 显式 add_block 存在时才需要查；顺带确保拓扑已建。
## 普通地图（无壁垒）完全跳过 EnemyNavField，不触发一次性的拓扑构建开销。
static func _walls_available() -> bool:
	var frame := Engine.get_physics_frames()
	if _walls_probe_frame == frame:
		return _walls_probe_ok
	_walls_probe_frame = frame
	_walls_probe_ok = EnemyNavField.has_blocks() and EnemyNavField.ensure_topology()
	return _walls_probe_ok
