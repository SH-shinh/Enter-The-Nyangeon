# 参考 pixelfx scifi/scanner（MIT）：准星锁定框，像素短边 + 四角括号 + 呼吸。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")

static var meta := {
	"name": "Hare lock cursor",
	"desc": "A pixel bracket frame breathing in yellow-green.",
	"tags": ["scifi", "lock", "cursor", "target", "loop"],
	"size": [128, 128],
	"origin": [64, 64],
	"duration": 1.6,
	"loop": true,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#0a1400", "#1c2e00", "#3f5c00", "#6f8f00", "#a8c400", "#d6f04a", "#f2ffb0", "#ffffff"],
		"seed": 22,
	},
}

const D := 1.6
const B := 58.0
const ARM := 12.0


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var pulse := 0.72 + 0.28 * sin(t * TAU / D)
	var inner: float = B * 0.55

	# 四角 L：3px 粗 + 内圈小角标 + 角光
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var x: float = sx * B
			var y: float = sy * B
			p.line(x, y, x - sx * ARM, y, C[7], 0.95 * pulse)
			p.line(x, y + sy, x - sx * ARM, y + sy, C[6], 0.9 * pulse)
			p.line(x, y - sy * 2.0, x - sx * ARM, y - sy * 2.0, C[5], 0.7 * pulse)
			p.line(x, y, x, y - sy * ARM, C[7], 0.95 * pulse)
			p.line(x + sx, y, x + sx, y - sy * ARM, C[6], 0.9 * pulse)
			p.line(x + sx * 2.0, y, x + sx * 2.0, y - sy * ARM, C[5], 0.7 * pulse)
			# 内圈小 L：双层锁定感
			var ix: float = sx * inner
			var iy: float = sy * inner
			p.line(ix, iy, ix - sx * 5.0, iy, C[5], 0.5 * pulse)
			p.line(ix, iy, ix, iy - sy * 5.0, C[5], 0.5 * pulse)
			p.dot(x, y, C[7], pulse)
			p.glow(x, y, 5.0, C[4], 0.3 * pulse)

	# 像素短边：每 12px 一段、8px 实线
	for i in range(-58, 58, 12):
		var x0: float = float(i)
		p.line(x0, -B, x0 + 8.0, -B, C[5], 0.55 * pulse)
		p.line(x0, B, x0 + 8.0, B, C[5], 0.55 * pulse)
		p.line(-B, x0, -B, x0 + 8.0, C[5], 0.55 * pulse)
		p.line(B, x0, B, x0 + 8.0, C[5], 0.55 * pulse)

	# 中心小十字
	p.line(-6.0, 0.0, 6.0, 0.0, C[6], 0.6 * pulse)
	p.line(0.0, -6.0, 0.0, 6.0, C[6], 0.6 * pulse)
