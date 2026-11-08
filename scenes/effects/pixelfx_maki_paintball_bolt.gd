# 参考 pixelfx arcane/arcane-missiles（MIT，弹头 head 部分）：
# 单发颜料弹的弹头；拖尾由运行时 maki_paintball_trail.gd 沿真实飞行轨迹绘制。
# 绘制坐标以 meta.origin 为 (0,0)。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const WHITE := Px.WHITE

const D := 0.22

static var meta := {
	"name": "Maki paintball head",
	"desc": "A single paint head: spinning rays and a colored core with a white heart.",
	"tags": ["projectile", "paint", "one-shot"],
	"size": [64, 64],
	"origin": [32, 32],
	"duration": 0.22,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#2a0f1c", "#5c1f38", "#a83a63", "#e86a9a", "#ff9cc0", "#ffc4da", "#ffe0ee", "#ffffff"],
		"seed": 6,
	},
}


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	if t >= D:
		return
	var C := Px.fit(o.palette, 8)
	# 弹头：4 条旋转光条 + 彩色同心圆 + 小白色核心
	for i in 4:
		var a2: float = t * 24.0 + (i * TAU) / 4.0
		var l := 7.5 + 2.0 * sin(t * 50.0 + i)
		p.line(cos(a2) * 4.4, sin(a2) * 4.4, cos(a2) * l, sin(a2) * l, C[6])
	p.circle(0.0, 0.0, 5.4, C[3])
	p.circle(0.0, 0.0, 4.4, C[4])
	p.circle(0.0, 0.0, 3.1, C[5])
	p.circle(0.0, 0.0, 1.7, C[6])
	p.circle(0.0, 0.0, 0.8, WHITE)
	p.glow(0.0, 0.0, 22.0, int(C[5]), 0.55)
	p.glow(0.0, 0.0, 8.0, WHITE, 0.35)
