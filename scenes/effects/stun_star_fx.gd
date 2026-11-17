extends Node2D

## 眩晕（stun）星星环：参考 pixelfx status/stunned 的 bodyless 头顶环。
## 跟随目标并按 hurtbox 体型缩放；玩家/召唤物跳跃时按 sprite_2d 的 y 偏移把星星抬到头顶上方。
## 循环播放，由 stun_component 在 buff 生效/移除时 play_anim / idle_state。

const FRAMES := preload("res://scenes/effects/stun_star_frames.res")
const ORIGIN := Vector2(24, 20)
const BODY_REF_WIDTH := 24.0
const FALLBACK_SIZE := 48.0
const MEASURE_INTERVAL := 0.25
## 地面时 sprite_2d.position.y 的基准值（玩家/召唤物场景一致）。敌人无跳跃，clamp 后为 0。
const GROUND_SPRITE_Y := -17.0
## 星星环中心比头顶再高一点，避免压住眼睛。
const HEAD_GAP := 4.0
## 整体视觉缩放：参考库星星环在 640×360 下偏大，统一缩 50%（2026-11-15 用户反馈）。
const SIZE_MULT := 0.5

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
	_sprite.offset = -ORIGIN
	PoolManager.add_pool("stun_star_fx", self)
	idle_state()


func idle_state() -> void:
	is_idle = 1
	visible = false
	_sprite.stop()
	target = null


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
		idle_state()
		return
	_measure_wait -= delta
	_refresh_anchor()


## 头顶 = hurtbox 中心减半高；再叠加 sprite_2d 的跳跃位移（地面 -17，空中更小 → 正上方偏移）。
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
	var head_local := _cached_center + Vector2(0.0, -_cached_size.y * 0.5)
	var jump := 0.0
	var sprite = body.get("sprite_2d")
	if sprite != null and sprite is Node2D:
		jump = clampf(GROUND_SPRITE_Y - (sprite as Node2D).position.y, 0.0, 200.0)
	# Godot y 轴向下：跳得越高（sprite.position.y 越小），星星的世界 y 越小（越靠上）。
	global_position = body.to_global(head_local) + Vector2(0.0, -jump - HEAD_GAP)
	var sx := clampf(_cached_size.x / BODY_REF_WIDTH, 0.8, 2.0) * SIZE_MULT
	scale = Vector2(sx, sx)
