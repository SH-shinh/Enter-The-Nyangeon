extends Node2D
## PLACEHOLDER：感电单链的临时电弧表现，下一轮替换为参考库（pixelfx lightning/chain-lightning）风格。
##
## 冻结接口：play(points: Array[Vector2], power: int)
## 池契约：is_idle / idle_state() / PoolManager.add_pool("shock_chain", self)

const POOL_ID := "shock_chain"
const CORE_COLOR := Color(0.88, 1.0, 1.0, 1.0)
const GLOW_COLOR := Color(0.482, 0.549, 1.0, 0.35)
const NODE_GLOW := Color(0.482, 0.549, 1.0, 0.30)
const LIFE := 0.18
const REFRESH := 0.04

var is_idle: int = 1

var _points: Array[Vector2] = []
var _segments: Array[PackedVector2Array] = []
var _power: int = 1
var _age: float = 0.0
var _refresh: float = 0.0


func _ready() -> void:
	PoolManager.add_pool(POOL_ID, self)
	visible = false
	set_process(false)


func idle_state() -> void:
	reset_physics_interpolation()
	is_idle = 1
	visible = false
	modulate.a = 1.0
	_points.clear()
	_segments.clear()
	_age = 0.0
	_refresh = 0.0
	set_process(false)
	queue_redraw()


func play(points: Array[Vector2], power: int) -> void:
	if points.size() < 2:
		return
	reset_physics_interpolation()
	global_position = Vector2.ZERO
	is_idle = 0
	visible = true
	modulate.a = 1.0
	_power = maxi(1, power)
	_age = 0.0
	_refresh = 0.0
	_points.clear()
	for p in points:
		_points.append(to_local(p))
	_rebuild()
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_age += delta
	_refresh += delta
	if _refresh >= REFRESH and _age < LIFE * 0.65:
		_refresh = 0.0
		_rebuild()
	if _age > LIFE * 0.6:
		modulate.a = clampf((LIFE - _age) / (LIFE * 0.4), 0.0, 1.0)
	queue_redraw()
	if _age >= LIFE:
		idle_state()


func _rebuild() -> void:
	_segments.clear()
	for i in _points.size() - 1:
		var a := _points[i]
		var b := _points[i + 1]
		var length := a.distance_to(b)
		if length < 1.0:
			continue
		var segments := clampi(int(length / 8.0), 3, 14)
		var dir := (b - a) / length
		var normal := Vector2(-dir.y, dir.x)
		var pts := PackedVector2Array()
		for s in segments + 1:
			var t := float(s) / float(segments)
			var p := a.lerp(b, t)
			if s > 0 and s < segments:
				p += normal * randf_range(-6.0, 6.0) + dir * randf_range(-3.0, 3.0)
			pts.append(p)
		_segments.append(pts)


func _draw() -> void:
	if _points.size() < 2:
		return
	var core_width := 1.0 + float(_power - 1) * 0.25
	for pts in _segments:
		draw_polyline(pts, GLOW_COLOR, 3.0 + core_width)
		draw_polyline(pts, CORE_COLOR, core_width)
	for p in _points:
		draw_circle(p, 4.0, NODE_GLOW)
		draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), Color(1, 1, 1, 0.95))
