extends Node2D

## 腐化敌人身上的常驻光环：世界坐标跟随目标，播放烘焙图集。
## 由 corruption_field_component 在挂上 buff 时创建、清除 buff / 死亡时释放。
##
## 锚点按**敌人身体**适配：ENN 的 body 原点不一定是脚底（有的敌人原点在脚底，有的在中心），
## 所以用 HurtBoxMeasure 取 hurtbox 的本地中心与尺寸，算出脚底，再按身高等比缩放。

const FRAMES := preload("res://scenes/effects/corruption_aura_frames.res")
## 与 pixelfx_corruption_aura.gd 的 meta.origin 对应
const AURA_ORIGIN := Vector2(36, 64)
## 效果里"虚拟身体"的高度（px），用来把光环缩放到实际体型
const BODY_REF_HEIGHT := 36.0
## 找不到 hurtbox 时的兜底直径
const FALLBACK_SIZE := 48.0
## 体型测量的重算间隔（秒）；平时只做脚底跟随，避免每物理帧 measure
const MEASURE_INTERVAL := 0.25

var target: Node
var is_idle: int = 1

var _cached_size := Vector2.ZERO
var _cached_center := Vector2.ZERO
var _cached_body_scale := Vector2.ZERO
var _measure_wait := 0.0

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	_sprite.sprite_frames = FRAMES
	_sprite.centered = false
	_sprite.offset = -AURA_ORIGIN
	idle_state()


func idle_state() -> void:
	is_idle = 1
	visible = false
	target = null
	_sprite.stop()


func follow_body(body: Node) -> void:
	target = body


func play_anim() -> void:
	is_idle = 0
	visible = true
	_measure_wait = 0.0
	_refresh_anchor()
	_sprite.play("default")


func _physics_process(delta: float) -> void:
	if is_idle == 1:
		return
	if target == null or not is_instance_valid(target) or not (target is Node2D):
		# 目标已回池/释放（回合清场走 queue_free，不触发组件 deactivate）：
		# 不能只隐藏，否则光环会作为孤儿节点挂在 YSort 上跨回合累积。
		idle_state()
		queue_free()
		return
	_measure_wait -= delta
	_refresh_anchor()


## 脚底 = hurtbox 本地中心 + 半高；缩放 = hurtbox 高 / 效果身体高（夹在 0.9–1.8）。
## 每物理帧只跟随位置（敌人按 60fps 移动，改 10Hz 跟随会明显脱节），体型测量按
## 0.25s / 缩放变化缓存；scale 只在真的变化时写，省掉多余的 transform 通知与 YSort 重排。
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
	var feet := _cached_center + Vector2(0.0, _cached_size.y * 0.5)
	global_position = body.to_global(feet)
	var s := clampf(_cached_size.y / BODY_REF_HEIGHT, 0.9, 1.8)
	if not is_equal_approx(scale.x, s) or not is_equal_approx(scale.y, s):
		scale = Vector2(s, s)
