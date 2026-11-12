extends Node2D
## DOT 常驻光环（燃烧 / 中毒共用一套逻辑，靠导出属性区分）。
##
## 纯视觉：跟随目标、按 hurtbox 尺寸适配、循环播放烘焙帧（`scenes/effects/*_aura_frames.res`）。
## - 锚点用 hurtbox 的**中心**（不是脚底）——这两个光环不画任何贴地元素；
## - `flare()` 由 DOT 跳伤调用，做一次 0.14s 的提亮脉冲（伤害反馈）；
## - `set_strength(layer)` 把层数映射成播放速度与不透明度（层数越高烧得/毒得越猛）；
## - 目标失效或敌人回池（`is_idle == 1`）时自我隐藏并释放，避免跨回合残留。

## 与效果脚本 meta.origin 对应（画布 80×80，原点在身体中心）
@export var frames: SpriteFrames
@export var origin: Vector2 = Vector2(40, 40)

## 效果里"虚拟身体"的高度（px），用来把光环缩放到实际体型
const BODY_REF_HEIGHT := 36.0
## 找不到 hurtbox 时的兜底直径
const FALLBACK_SIZE := 48.0
## 体型测量的重算间隔（秒）
const MEASURE_INTERVAL := 0.25
## 跳伤脉冲的时长（秒）。>1 的提亮依靠项目已开启的 hdr_2d。
## 中毒 0.3s 一跳，用 0.09s；燃烧 2s 一跳，用 0.14s。时长别超过跳伤间隔的一半，否则会变成持续闪烁。
@export var flare_time: float = 0.14

## 跳伤脉冲的提亮色：燃烧偏暖白、中毒偏绿白（由场景导出覆盖）
@export var flare_tint: Color = Color(1.8, 1.5, 1.2, 1.0)

var target: Node
var is_idle: int = 1

var _cached_size := Vector2.ZERO
var _cached_center := Vector2.ZERO
var _cached_body_scale := Vector2.ZERO
var _measure_wait := 0.0
## 脉冲剩余强度 1→0；0 表示没有脉冲在跑（此时不写 modulate）。
## 高频跳伤下不要用 create_tween()：中毒 0.3s 一跳、30 个中毒敌人 ≈ 100 个 Tween/秒。
var _flare_t := 0.0

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	_sprite.sprite_frames = frames
	_sprite.centered = false
	_sprite.offset = -origin
	idle_state()


func idle_state() -> void:
	is_idle = 1
	visible = false
	target = null
	_sprite.stop()
	# 复用前必须清掉上一跳的亮度，否则重新挂上时会先亮一下
	_flare_t = 0.0
	_sprite.modulate = Color.WHITE


func follow_body(body: Node) -> void:
	target = body


func play_anim() -> void:
	is_idle = 0
	visible = true
	_measure_wait = 0.0
	_refresh_anchor()
	if not _sprite.is_playing():
		# 复用时必须回到第 0 帧，否则会从上一轮停住的那一帧接着播
		_sprite.set_frame(0)
		_sprite.play("default")


## 层数 → 强度：提亮 + 不透明度（**不改 speed_scale**，改播放速度会破坏 30fps 的节奏）
func set_strength(layer: int) -> void:
	var l := maxi(1, layer)
	var b := clampf(1.0 + 0.10 * float(l - 1), 1.0, 1.35)
	modulate = Color(b, b, b, clampf(0.80 + 0.05 * float(l), 0.80, 1.0))


## DOT 跳一下：短促提亮，给"这一跳打到了"的反馈。
## 只置标志 + 立刻写一次，衰减在 _physics_process 里做（不创建 Tween）。
func flare() -> void:
	if _sprite == null:
		return
	_flare_t = 1.0
	_sprite.modulate = flare_tint


## 脉冲衰减：只在 _flare_t > 0 时写 modulate，归零后收尾写一次白就停。
## ease-out（k²）比线性更像"闪一下"：起手亮、收得快。
func _tick_flare(delta: float) -> void:
	if _flare_t <= 0.0:
		return
	_flare_t = maxf(0.0, _flare_t - delta / maxf(0.01, flare_time))
	if _flare_t <= 0.0:
		_sprite.modulate = Color.WHITE
	else:
		_sprite.modulate = Color.WHITE.lerp(flare_tint, _flare_t * _flare_t)


func _physics_process(delta: float) -> void:
	# 脉冲衰减放在早退之前：即使这一帧目标判定失败，也已经把上一帧的亮度收掉了
	_tick_flare(delta)
	if is_idle == 1:
		return
	if target == null or not is_instance_valid(target) or not (target is Node2D):
		idle_state()
		queue_free()
		return
	# 敌人回池（is_idle == 1）：光环必须跟着消失，否则会挂在 YSort 上跨回合累积
	if int(target.get("is_idle")) == 1:
		idle_state()
		queue_free()
		return
	_measure_wait -= delta
	_refresh_anchor()


## 以 hurtbox 中心为锚点（不贴地），缩放按 hurtbox 高 / 效果虚拟身体高。
## 每物理帧只跟随位置；体型测量按 0.25s / 缩放变化缓存。
func _refresh_anchor() -> void:
	if target == null or not is_instance_valid(target) or not (target is Node2D):
		return
	var body := target as Node2D
	var body_scale := body.global_transform.get_scale()
	if _measure_wait <= 0.0 or _cached_size == Vector2.ZERO or body_scale != _cached_body_scale:
		var m := HurtBoxMeasure.measure(body, FALLBACK_SIZE)
		_cached_size = m["size"]
		_cached_center = m["center"]
		_cached_body_scale = body_scale
		_measure_wait = MEASURE_INTERVAL
	global_position = body.to_global(_cached_center)
	var s := clampf(_cached_size.y / BODY_REF_HEIGHT, 0.9, 1.8)
	if not is_equal_approx(scale.x, s) or not is_equal_approx(scale.y, s):
		scale = Vector2(s, s)
