# 参考 pixelfx holy/heal 的 hoop/花瓣（MIT），bodyless：脚下光环扩散 + 光瓣绽开。
# 环体用 p.px + 调色板降级（alpha 抖动会把 1px 环碎成网点）。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Serina burst",
	"desc": "A hoop of light rolls out from the feet, a second faint hoop chases it, and petals of light bloom and fade.",
	"tags": ["holy", "heal", "burst", "one-shot"],
	"size": [96, 96],
	"origin": [48, 48],
	"duration": 0.9,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#2a0f1c", "#5c1f38", "#a83a63", "#e86a9a", "#ff9cc0", "#ffc4da", "#ffe0ee", "#ffffff"],
		"seed": 6,
	},
}

const D := 0.9
const R_MAX := 40.0


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	if t >= D:
		return
	var C := Px.fit(o.palette, 8)
	var gl := float(o.seed)

	# 两圈扩散光环
	for ring in 2:
		var at := float(ring) * 0.1
		var age := t - at
		if age < 0.0 or age > 0.5:
			continue
		var k := age / 0.5
		var r := 4.0 + (R_MAX - 4.0) * Px.Ease.outCubic(k)
		var n := maxi(32, int(ceil(TAU * r)) * 2)
		for j in n:
			var g := (j / float(n)) * TAU
			var c: int
			if k < 0.2:
				c = WHITE if ring == 0 else C[6]
			elif k < 0.5:
				c = C[6] if ring == 0 else C[5]
			elif k < 0.8:
				c = C[4] if ring == 0 else C[3]
			else:
				c = C[2] if ring == 0 else C[1]
			p.px(cos(g) * r, sin(g) * r, c)
			# 2px 粗：向内侧再补一像素（内圈更实）
			p.px(cos(g) * (r - 0.8), sin(g) * (r - 0.8), c)
		p.glow(0.0, 0.0, r + 6.0, C[4], 0.14 * (1.0 - k))

	# 脚边绽开的光瓣
	var bloom := minf(1.0, t / 0.25)
	for i in 6:
		var g := (i / 6.0) * TAU + gl
		var d := 8.0 + 16.0 * Px.Ease.outCubic(bloom)
		var fade := clampf(1.0 - (t - 0.2) / 0.5, 0.0, 1.0)
		if fade <= 0.0:
			continue
		var x := cos(g) * d
		var y := sin(g) * d
		var c2: int = C[6] if fade > 0.6 else (C[5] if fade > 0.3 else C[4])
		p.px(x, y, c2)
		p.px(x * 0.72, y * 0.72, C[4])
		p.light(x, y, C[5], 0.5 * fade)

	# 起始柔光（光层，不抖动）
	if t < 0.2:
		var k2 := t / 0.2
		p.glow(0.0, 0.0, 26.0, C[6], 0.55 * (1.0 - k2))
