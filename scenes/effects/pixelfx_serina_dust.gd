# 上浮光尘（做成一次性小烟团，由 mote_spawner 池化；世界坐标播放）。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Serina dust",
	"desc": "A few motes of light drift up and twinkle out.",
	"tags": ["holy", "dust", "mote", "one-shot"],
	"size": [32, 32],
	"origin": [16, 24],
	"duration": 0.7,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#2a0f1c", "#5c1f38", "#a83a63", "#e86a9a", "#ff9cc0", "#ffc4da", "#ffe0ee", "#ffffff"],
		"seed": 9,
	},
}

const D := 0.7


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	if t >= D:
		return
	var C := Px.fit(o.palette, 8)
	Px.cycle(t, D, 4, float(o.seed) + 9.0, func(r: Px.Rng): return r.range(0.45, 0.7), func(age: float, life: float, r: Px.Rng):
		var u := age / life
		var x0 := r.range(-8.0, 8.0)
		var y0 := r.range(-2.0, 2.0)
		var x := x0 + sin(age * 5.0 + x0) * 1.2
		var y := y0 - r.range(12.0, 20.0) * u
		var tw := 0.6 + 0.4 * sin(age * 22.0 + x0 * 3.0)
		var a := sin(u * PI) * tw
		p.dot(x, y, WHITE if tw > 0.85 else C[6], a)
		p.light(x, y, C[5], 0.45 * a))
