extends Node2D

## Kotama 全息影像的环绕光点：少量像素粒子围绕角色投影旋转，ADD 材质补光。
## 只负责绘制，不参与碰撞/嘲讽；透明度由 KotamaHologram 用 modulate.a 统一控制。

@export var particle_count: int = 10
@export var radius_x: float = 27.0
@export var radius_y: float = 11.0
@export var orbit_speed: float = 1.15

const COLORS := [
	Color(1.0, 1.0, 1.0, 1.0),
	Color(0.78, 0.93, 1.0, 1.0),
	Color(0.43, 0.81, 1.0, 1.0),
]

var _time: float = 0.0

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	for i in particle_count:
		var phase: float = float(i) * TAU / float(max(1, particle_count)) + 0.7 * sin(float(i) * 2.3)
		var speed: float = orbit_speed * (0.72 + 0.42 * fmod(float(i) * 0.37, 1.0))
		var angle: float = _time * speed + phase
		var lift: float = sin(_time * 1.4 + phase * 1.3) * 1.4
		var pos := Vector2(cos(angle) * radius_x, sin(angle) * radius_y + lift)
		var twinkle: float = 0.55 + 0.45 * sin(_time * 2.6 + phase * 3.0)
		var col: Color = COLORS[i % COLORS.size()]
		var px := Vector2(floor(pos.x), floor(pos.y))
		# 3x3 低 alpha 光晕 + 1x1 亮芯。
		draw_rect(Rect2(px - Vector2(1, 1), Vector2(3, 3)), Color(col.r, col.g, col.b, 0.12 * twinkle))
		draw_rect(Rect2(px, Vector2(1, 1)), Color(col.r, col.g, col.b, 0.75 * twinkle))
