extends Node2D
## 感电链的加色发光层：ADD 材质在 shock_chain_arc.tscn 里设置。
##
## 实测本项目 2D canvas 不参与 Environment glow，HDR >1 不会 bloom；
## 所以发光靠这个子节点手动叠 3 层由宽到窄的加色折线 + 节点柔光。
## 父节点负责叫 sync()，并靠 modulate 向下继承统一淡出。

const GLOW_TEX := preload("res://sprites/particle/circular_1.png")

const GLOW_WIDE := Color(0.42, 0.40, 0.95, 0.16)
const GLOW_MID := Color(0.55, 0.55, 1.0, 0.20)
const GLOW_TIGHT := Color(0.85, 0.88, 1.0, 0.48)
const NODE_GLOW := Color(0.80, 0.85, 1.0, 0.80)

var _segments: Array = []
var _points: Array = []
var _power: int = 1


func sync(segments: Array, points: Array, power: int) -> void:
	_segments = segments
	_points = points
	_power = maxi(1, power)
	queue_redraw()


func _draw() -> void:
	if _segments.is_empty():
		return
	for pts in _segments:
		draw_polyline(pts, GLOW_WIDE, 12.0)
		draw_polyline(pts, GLOW_MID, 8.0)
		draw_polyline(pts, GLOW_TIGHT, 4.0)
	var r := 6.0 + float(_power)
	for p in _points:
		draw_texture_rect(GLOW_TEX, Rect2(p - Vector2(r, r), Vector2(r * 2, r * 2)), false, NODE_GLOW)
