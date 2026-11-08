extends Node2D

## 恶寒（chill）tick 特效：上方落雪、身上冰晶闪烁、左右抖动后向下抖落的碎晶。
## 参考 pixelfx status/frozen；bodyless，不重绘身体、不画冰壳/霜蕨/地面。
## 跟随目标并按 hurtbox 体型缩放（脚底锚定），走 PoolManager 的 follow-fx 契约。

const FRAMES := preload("res://scenes/effects/chill_frozen_frames.res")
const MIST_FRAMES := preload("res://scenes/effects/chill_mist_frames.res")
const ORIGIN := Vector2(32, 64)
const MIST_ORIGIN := Vector2(8, 14)
const BODY_REF_WIDTH := 24.0
const BODY_REF_HEIGHT := 36.0
const FALLBACK_SIZE := 48.0
const MEASURE_INTERVAL := 0.25

var target: Node
var is_idle: int = 1

var _cached_size := Vector2.ZERO
var _cached_center := Vector2.ZERO
var _cached_body_scale := Vector2.ZERO
var _measure_wait := 0.0

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _mist: AnimatedSprite2D = $Mist


func _ready() -> void:
	_sprite.sprite_frames = FRAMES
	_sprite.centered = false
	_sprite.offset = -ORIGIN
	_sprite.animation_finished.connect(_on_finished)
	_mist.sprite_frames = MIST_FRAMES
	_mist.centered = false
	_mist.offset = -MIST_ORIGIN
	_mist.animation_finished.connect(_on_mist_finished)
	PoolManager.add_pool("chill", self)
	idle_state()


func idle_state() -> void:
	is_idle = 1
	visible = false
	_sprite.stop()
	_mist.stop()
	_mist.visible = false
	target = null


func follow_body(body: Node) -> void:
	target = body


func play_anim() -> void:
	is_idle = 0
	visible = true
	_measure_wait = 0.0
	_refresh_anchor()
	_sprite.play("default")
	# 吐息：世界坐标（top_level），播放瞬间定在嘴部高度
	var mouth := global_position + Vector2(0.0, -_cached_size.y * 0.55)
	_mist.global_position = mouth
	var ms := clampf(_cached_size.y / BODY_REF_HEIGHT, 0.8, 2.0)
	_mist.scale = Vector2(ms, ms)
	_mist.visible = true
	_mist.play("default")


func _physics_process(delta: float) -> void:
	if is_idle == 1:
		return
	if target != null and is_instance_valid(target) and target is Node2D:
		_measure_wait -= delta
		_refresh_anchor()
	else:
		idle_state()


## 脚底 = hurtbox 本地中心 + 半高；非等比缩放让宽体型也包得住。
## 每物理帧只跟随位置，体型测量按 0.25s / 缩放变化缓存。
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
	var sx := clampf(_cached_size.x / BODY_REF_WIDTH, 0.9, 2.2)
	var sy := clampf(_cached_size.y / BODY_REF_HEIGHT, 0.8, 2.0)
	scale = Vector2(sx, sy)


func _on_finished() -> void:
	idle_state()


func _on_mist_finished() -> void:
	_mist.stop()
	_mist.visible = false



