extends Node2D

## Maki 彩弹：单发抛射颜料弹（飞行 → 命中 pop → 回池）。
## 3 色变体与 script/floor_paint.gd 的 0=Pink / 1=Blue / 2=Yellow 索引对齐。
## 弹道为二次贝塞尔（向上抛），时长/弧高按距离缩放；节点旋转跟随轨迹切线。

const POOL_ID := "maki_paintball"
const BOLT_ORIGIN := Vector2(32, 32)
const POP_ORIGIN := Vector2(36, 36)
const BOLT_FRAMES: Array[SpriteFrames] = [
	preload("res://scenes/effects/maki_paintball_bolt_0.res"),
	preload("res://scenes/effects/maki_paintball_bolt_1.res"),
	preload("res://scenes/effects/maki_paintball_bolt_2.res"),
]
const POP_FRAMES: Array[SpriteFrames] = [
	preload("res://scenes/effects/maki_paintball_pop_0.res"),
	preload("res://scenes/effects/maki_paintball_pop_1.res"),
	preload("res://scenes/effects/maki_paintball_pop_2.res"),
]

## 抛射参数：按距离缩放。900 px/s → 最慢 0.55s；弧高随距离 16~40px。
const FLY_SPEED := 900.0
const FLY_MIN := 0.32
const FLY_MAX := 0.55
const ARC_RATIO := 0.16
const ARC_MIN := 16.0
const ARC_MAX := 40.0

const PAINT_GROUND_SCENE: PackedScene = preload("res://script/paint_ground.tscn")

@export var fly_seconds: float = 0.32
@export var pop_seconds: float = 0.38

var is_idle: int = 1
var color_index: int = 0
var arc_height: float = 0.0

var _fly_from := Vector2.ZERO
var _fly_mid := Vector2.ZERO
var _fly_to := Vector2.ZERO
var _arrive_cb := Callable()
## 远端纯表现克隆（mod 通用视觉通道调用 network_apply_visual 时置位）
var _remote: bool = false
var _splat_at := Vector2.ZERO
var _splat_radius: float = 80.0
var _splat_angle: float = NAN
var _splat_scale: float = 1.0
var _splat_shape: int = -1

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var trail = $Trail

var _tween: Tween


func _ready() -> void:
	sprite.centered = false
	PoolManager.add_pool(POOL_ID, self)


## from/to 为世界坐标；color 取 0..2（粉/蓝/黄）；arrive_cb 在到达落点瞬间调用（用于铺地面颜料）。
func active_state(from: Vector2, to: Vector2, color: int, arrive_cb: Callable = Callable()) -> void:
	_kill_tween()
	reset_physics_interpolation()
	is_idle = 0
	_arrive_cb = arrive_cb
	color_index = clampi(color, 0, BOLT_FRAMES.size() - 1)
	visible = true
	_fly_from = from
	_fly_to = to
	var dist := from.distance_to(to)
	fly_seconds = clampf(dist / FLY_SPEED, FLY_MIN, FLY_MAX)
	arc_height = clampf(dist * ARC_RATIO, ARC_MIN, ARC_MAX)
	_fly_mid = (from + to) * 0.5 + Vector2(0, -arc_height)
	trail.clear()
	trail.begin(color_index)
	_set_arc_t(0.0)
	sprite.offset = -BOLT_ORIGIN
	sprite.sprite_frames = BOLT_FRAMES[color_index]
	var frames: int = BOLT_FRAMES[color_index].get_frame_count("default")
	var fps: float = maxf(1.0, BOLT_FRAMES[color_index].get_animation_speed("default"))
	sprite.speed_scale = clampf((float(frames) / fps) / fly_seconds, 0.3, 1.0)
	sprite.play("default")
	_tween = create_tween()
	_tween.tween_method(_set_arc_t, 0.0, 1.0, fly_seconds)
	_tween.tween_callback(_on_arrive)


## 联机通用视觉通道入口：远端克隆用同一套 from/to/color 重放（纯表现，不结算、不播本机音效）。
func network_apply_visual(params: Dictionary) -> void:
	_remote = true
	var from_v = params.get("from", global_position)
	var to_v = params.get("to", Vector2.ZERO)
	var splat_v = params.get("splat_at", Vector2.ZERO)
	var color_v = params.get("color", 0)
	var radius_v = params.get("radius", 80.0)
	var angle_v = params.get("angle", NAN)
	var scale_v = params.get("scale", 1.0)
	var shape_v = params.get("shape", -1)
	_splat_at = splat_v if splat_v is Vector2 else Vector2.ZERO
	_splat_radius = float(radius_v) if (radius_v is int or radius_v is float) else 80.0
	_splat_angle = float(angle_v) if (angle_v is int or angle_v is float) else NAN
	_splat_scale = float(scale_v) if (scale_v is int or scale_v is float) else 1.0
	_splat_shape = int(shape_v) if (shape_v is int or shape_v is float) else -1
	var from: Vector2 = from_v if from_v is Vector2 else global_position
	var to: Vector2 = to_v if to_v is Vector2 else from
	var color: int = int(color_v) if (color_v is int or color_v is float) else 0
	active_state(from, to, color)


## 二次贝塞尔：起手向上、越过中线、落向目标；rotation 取轨迹切线。
func _set_arc_t(t: float) -> void:
	var u := 1.0 - t
	global_position = _fly_from * (u * u) + _fly_mid * (2.0 * u * t) + _fly_to * (t * t)
	trail.push(global_position)
	var tangent := (_fly_mid - _fly_from) * (2.0 * u) + (_fly_to - _fly_mid) * (2.0 * t)
	if tangent.length_squared() > 0.0001:
		rotation = tangent.angle()


func _on_arrive() -> void:
	trail.finish()
	rotation = 0.0
	sprite.speed_scale = 1.0
	sprite.offset = -POP_ORIGIN
	sprite.sprite_frames = POP_FRAMES[color_index]
	sprite.play("default")
	if _arrive_cb.is_valid():
		_arrive_cb.call()
	_arrive_cb = Callable()
	# 远端克隆没有投掷者 PS 的到达回调：在本地铺一块同色地面颜料（纯表现）。
	if _remote and _splat_at != Vector2.ZERO:
		_spawn_remote_splat()
	_tween = create_tween()
	_tween.tween_interval(pop_seconds)
	_tween.tween_callback(idle_state)


func _spawn_remote_splat() -> void:
	var layer: Node = get_tree().get_first_node_in_group("FloorLayer")
	if layer == null:
		return
	var ground := layer.get_node_or_null("PaintGround")
	if ground == null:
		ground = PAINT_GROUND_SCENE.instantiate()
		ground.name = "PaintGround"
		layer.add_child(ground)
	ground.add_paint(_splat_at, color_index, _splat_radius, _splat_angle, _splat_scale, _splat_shape)


func idle_state() -> void:
	_kill_tween()
	_arrive_cb = Callable()
	_remote = false
	_splat_at = Vector2.ZERO
	_splat_radius = 80.0
	_splat_angle = NAN
	_splat_scale = 1.0
	_splat_shape = -1
	trail.clear()
	is_idle = 1
	visible = false
	sprite.stop()
	global_position = Vector2.ZERO
	rotation = 0.0


func clear_pool() -> void:
	PoolManager.erase_pool(POOL_ID)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
