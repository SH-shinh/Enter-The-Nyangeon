extends Node2D

## 弹壳：俯视角抛壳 → 落地弹跳 → 静止后长期留存。
##
## 参考 pixelfx `projectiles/muzzle-smg`（"brass casings bouncing on the floor"，MIT）
## 与 `_lib.gd:318 casing() / :348 drawCasing()` 的弹壳配方；库里弹壳是侧视、且烘在
## 枪口闪光的帧画布里，俯视角需要任意方向 + 地面高度投影，故只移植配方，运行期绘制。
##
## 池契约（对齐 `scenes/effects/stun_star_fx.gd` / `script/floor_paint.gd`）：
## `is_idle` / `idle_state()` / `PoolManager.add_pool("casing", self)`；
## 上限由 `PoolManager.IDLE_LIMITS["casing"]` 决定，满额环状复用最旧者。
##
## 关键约定：离地高度 height 只影响渲染（屏幕 -y），与玩家跳跃
## `sprite_2d.position.y = -17` 同一套「屏幕上方 = 更高」；不接物理层、不参与碰撞。
##
## 层级（2026-11-17 用户要求）：飞行期把 `z_index` 抬到世界层之上（盖过角色），
## 落地静止后 `z_index` 归 0，随所在层（`FloorLayer` 在 `YSort` 之前）自然落回地板。
## ⚠️ 这里**不能 reparent**：`PoolManager` 用 `tree_exiting` 做池自注销，而 `reparent()`
## 会触发 `tree_exiting` → 弹壳被踢出池、池条目被删（2026-11-17 实测），改用 z 切换。

const POOL_ID := "casing"

## 静止后继续滑行多久再彻底关物理（保留落地的小滑步手感）。
const SETTLE_TIME := 0.25
## 落地反光的持续时长（参考库 hit 白闪 0.07s）。
const SPARK_TIME := 0.07
## 离地高度达到此值时装在影子上的不透明度降到最低（不再做尺寸缩放）。
const HEIGHT_FOR_SHADOW_FADE := 22.0
const SHADOW_ALPHA_GROUND := 1.0
const SHADOW_ALPHA_AIR := 0.55

## 层级：飞行期压在世界层之上，静止后归 0 回到地板层。
const Z_FLY := 1
const Z_FLOOR := 0
## true = 落地静止（最后一次触地）才降回地板层；false = 首次触地就降。
const FLOOR_LAYER_ON_REST := true

## 抛壳速度/自旋区间（px/s、rad/s）。俯视角要能看出「甩出去」而不是原地掉。
const EJECT_SPEED_MIN := 55.0
const EJECT_SPEED_MAX := 105.0
## 竖直初速：用户要求弧顶高度再高 100%，按 h = vz^2 / 2g 取 vz * sqrt(2)（130/190 → 184/269）。
const EJECT_VZ_MIN := 183.8
const EJECT_VZ_MAX := 268.7
const EJECT_SPIN_MIN := 8.0
const EJECT_SPIN_MAX := 16.0
## 抛壳口落在枪身哪一侧：aim.orthogonal() 在 y 向下的屏幕里是瞄准方向的「左侧」，
## 取 -1 才是右射手的抛壳口（右侧）。
const EJECT_SIDE := -1.0
## 侧向偏转抖动（度）与向后偏移比例，让每发落点不重叠。
const EJECT_YAW_JITTER := 18.0
const EJECT_BACK_MIN := 0.15
const EJECT_BACK_MAX := 0.5

var is_idle: int = 1

var _state: Dictionary = CasingBallistic.initial_state(Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0)
var _settle_left: float = 0.0
var _spark_left: float = 0.0

@onready var _shadow: Sprite2D = $Shadow
@onready var _body: Sprite2D = $Body
@onready var _spark: Sprite2D = $Spark


func _ready() -> void:
	_shadow.texture = CasingTextures.shadow_texture()
	_body.texture = CasingTextures.body_texture()
	_spark.texture = CasingTextures.spark_texture()
	PoolManager.add_pool(POOL_ID, self)
	idle_state()


func idle_state() -> void:
	reset_physics_interpolation()
	is_idle = 1
	visible = false
	set_physics_process(false)
	z_index = Z_FLOOR
	_settle_left = 0.0
	_spark_left = 0.0
	_spark.visible = false
	_body.modulate = Color.WHITE
	_state = CasingBallistic.initial_state(Vector2.ZERO, Vector2.ZERO, 0.0, 0.0, 0.0)
	global_position = Vector2.ZERO
	_sync_visual()


## 从地面点 origin 抛出弹壳（视觉起点 = origin - (0, start_height)，即抛壳口本身）。
## 调用方保证已入树（@onready 已就绪）；start_height 由调用方按 Gun 的 y 算。
func active_state(origin: Vector2, aim: Vector2, start_height: float = 0.0) -> void:
	# 飞行期压在世界层之上（不换父节点，见文件头注释）。
	z_index = Z_FLY
	is_idle = 0
	visible = true
	global_position = origin
	reset_physics_interpolation()
	var dir: Vector2 = aim.normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var side := dir.orthogonal() * EJECT_SIDE
	# 侧向为主、略向后甩，避免弹壳落到枪口正前方。
	var eject := (side.rotated(deg_to_rad(randf_range(-EJECT_YAW_JITTER, EJECT_YAW_JITTER)))
			- dir * randf_range(EJECT_BACK_MIN, EJECT_BACK_MAX)).normalized()
	var spin_sign := -1.0 if randf() < 0.5 else 1.0
	_state = CasingBallistic.initial_state(
		origin,
		eject * randf_range(EJECT_SPEED_MIN, EJECT_SPEED_MAX),
		randf_range(EJECT_VZ_MIN, EJECT_VZ_MAX),
		randf_range(EJECT_SPIN_MIN, EJECT_SPIN_MAX) * spin_sign,
		randf_range(0.0, TAU),
		maxf(0.0, start_height)
	)
	_settle_left = 0.0
	_spark_left = 0.0
	_spark.visible = false
	_body.modulate = Color.WHITE
	_sync_visual()
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	var was_resting: bool = bool(_state.get("resting", false))
	_state = CasingBallistic.step(_state, delta)
	global_position = _state["pos"]
	if bool(_state.get("bounced", false)):
		_bounce_feedback()
	_sync_visual()

	if _spark_left > 0.0:
		_spark_left -= delta
		if _spark_left <= 0.0:
			_spark.visible = false

	var resting: bool = bool(_state.get("resting", false))
	if resting:
		if not was_resting:
			_settle_left = SETTLE_TIME
			if FLOOR_LAYER_ON_REST:
				_drop_to_floor_z()
		_settle_left -= delta
		if _settle_left <= 0.0:
			# 彻底静止：关物理，画面已定型；复用时只经 idle_state 重置。
			_state["vel"] = Vector2.ZERO
			_spark.visible = false
			set_physics_process(false)


## 落地反馈：一记软白闪（参考库 drawCasing 的 hit 白闪），俯视角下兼作蹬地的小尘。
func _bounce_feedback() -> void:
	_spark.visible = true
	_spark.modulate = Color(1.0, 0.96, 0.84, randf_range(0.35, 0.6))
	_spark_left = SPARK_TIME
	if not FLOOR_LAYER_ON_REST:
		_drop_to_floor_z()


## 静止后：z 归 0，随 `FloorLayer`（在 `YSort` 之前）落回地板层。
func _drop_to_floor_z() -> void:
	z_index = Z_FLOOR


## 影子固定在弹壳的地面位置（不随高度移动、不缩放），本体按离地高度向屏幕 -y 偏移。
func _sync_visual() -> void:
	var h: float = float(_state["height"])
	var t: float = clampf(h / HEIGHT_FOR_SHADOW_FADE, 0.0, 1.0)
	var ang: float = float(_state["ang"])
	# 只取整渲染位置；物理量保持浮点，避免落点抖动。
	_body.position = Vector2(0.0, -roundf(h))
	_body.rotation = ang
	_shadow.position = Vector2.ZERO
	_shadow.rotation = ang
	_shadow.scale = Vector2.ONE
	_shadow.modulate = Color(1.0, 1.0, 1.0, lerpf(SHADOW_ALPHA_GROUND, SHADOW_ALPHA_AIR, t))
	# 静止（离地 0）时影子被本体完全遮住，隐藏它省掉一次 draw call（2 → 1）。
	_shadow.visible = h > 0.0
