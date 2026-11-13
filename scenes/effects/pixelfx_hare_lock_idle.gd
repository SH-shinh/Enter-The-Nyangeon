# 参考 pixelfx scifi/scanner（MIT）：锁定完成后的呼吸框（无扫描线/残影，避免残留感）。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")

static var meta := {
	"name": "Hare lock idle",
	"desc": "The locked frame breathes in yellow-green.",
	"tags": ["scifi", "lock", "target", "loop"],
	"size": [64, 64],
	"origin": [32, 32],
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
const B := 16.0
const ARM := 6.0


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var pulse := 0.72 + 0.28 * sin(t * TAU / D)
	for sx: float in [-1.0, 1.0]:
		for sy2: float in [-1.0, 1.0]:
			var x: float = sx * B
			var y: float = sy2 * B
			p.line(x, y, x - sx * ARM, y, C[7], 0.9 * pulse)
			p.line(x, y + sy2, x - sx * ARM, y + sy2, C[5], 0.7 * pulse)
			p.line(x, y, x, y - sy2 * ARM, C[7], 0.9 * pulse)
			p.line(x + sx, y, x + sx, y - sy2 * ARM, C[5], 0.7 * pulse)
			p.line(x - sx * 2.0, y - sy2 * 2.0, x - sx * 5.0, y - sy2 * 2.0, C[4], 0.28 * pulse)
			p.line(x - sx * 2.0, y - sy2 * 2.0, x - sx * 2.0, y - sy2 * 5.0, C[4], 0.28 * pulse)
			p.dot(x, y, C[7], 0.95 * pulse)
			p.glow(x, y, 4.0, C[4], 0.22 * pulse)
	p.glow(0.0, 0.0, 12.0, C[4], 0.05 * pulse)
