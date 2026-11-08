# 参考 pixelfx status/frozen 的吐息（`frozen.gd:200-212`）：白雾团从嘴部扩散、上升、淡出。
# 一次性、世界坐标（由 chill_freeze_fx 在播放瞬间定在世界位置）。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Chill mist",
	"desc": "Breath steams out in pale puffs that swell, drift and fade.",
	"tags": ["ice", "chill", "mist", "breath", "one-shot"],
	"size": [24, 24],
	"origin": [8, 14],
	"duration": 0.8,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"],
		"seed": 7,
	},
}

const D := 0.8


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	if t >= D:
		return
	var C := Px.fit(o.palette, 8)

	# 4 团白雾错开发出：向外+向上漂，边漂边扩散
	for i in 4:
		var age := t - float(i) * 0.05
		if age < 0.0 or age > 0.65:
			continue
		var u := age / 0.65
		var x := 1.0 + (6.0 + float(i) * 1.5) * u
		var y := -float(i) * 0.5 - 5.0 * u
		var rad := 0.8 + 2.6 * sqrt(u)
		var a := 0.5 * (1.0 - u) * minf(1.0, u * 8.0)
		p.disc(x, y, rad, C[7], a)
		p.disc(x - rad * 0.2, y - rad * 0.3, rad * 0.5, WHITE, a * 0.8)
