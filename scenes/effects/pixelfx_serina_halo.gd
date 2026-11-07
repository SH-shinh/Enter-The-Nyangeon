# 参考 pixelfx holy/halo（MIT）：环形 shimmer + 绕环 glint + 眨眼星 + 辉光。
# 俯视改造：正圆小环（R=15）落在脚底平面，去掉原版侧视椭圆与 actor 打光。
# 注意：本项目的 painter 对 alpha<1 走 4×4 Bayer 抖动，1px 细线会碎成网点，
# 所以环体一律用 p.px + 调色板降级来表示明暗，只有辉光走 p.glow。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Serina halo",
	"desc": "A small pink ring of light circles the feet, a glint runs round it, stars wink on it and the light breathes once a second.",
	"tags": ["holy", "halo", "buff", "heal", "loop"],
	"size": [56, 56],
	"origin": [28, 28],
	"duration": 2.0,
	"loop": true,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#2a0f1c", "#5c1f38", "#a83a63", "#e86a9a", "#ff9cc0", "#ffc4da", "#ffe0ee", "#ffffff"],
		"seed": 4,
	},
}

const D := 2.0
const R := 15.0


static func apart(a: float, b: float) -> float:
	return absf(fmod(fmod(a - b + PI, TAU) + TAU, TAU) - PI)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph := (t / D) * TAU
	var pulse := 0.5 + 0.5 * sin(t * TAU)
	var breath := sin(t / D * TAU)
	# 像素感呼吸：半径按整数像素跳变（13↔17），不做亚像素缩放
	var rr := Px.round(R + 2.0 * breath)
	var gl := PI / 2.0 + ph

	var n := int(ceil(TAU * rr)) * 2
	for j in n:
		var g := (j / float(n)) * TAU
		var x := cos(g) * rr
		var y := sin(g) * rr
		var hot := apart(g, gl) < 0.26
		var shimmer := sin(g * 3.0 - ph * 2.0) > 0.72
		var c: int = WHITE if hot else (C[6] if shimmer else C[5])
		p.px(x, y, c)
		if j % 2 == 0:
			p.px(cos(g) * (rr - 3.0), sin(g) * (rr - 3.0), C[4])

	# 扩张段的回声环：方向感来自"胀出去"的那半拍
	if breath > 0.0:
		var echo := rr + 2.0
		var ne := int(ceil(TAU * echo))
		for j in ne:
			if j % 3 != 0:
				continue
			var g2 := (j / float(ne)) * TAU
			p.px(cos(g2) * echo, sin(g2) * echo, C[3])

	# 环心柔光：半径跟呼吸走
	p.glow(0.0, 0.0, rr + 10.0, C[4], 0.10 + 0.14 * pulse)
	p.glow(0.0, 0.0, 7.0, C[6], 0.08 + 0.05 * pulse)

	# 绕环 glint 的爆点
	if sin(gl) > -0.3:
		Px.sparkle(p, cos(gl) * rr, sin(gl) * rr, 1.2 + 1.6 * maxf(0.0, sin(gl)), WHITE, C[6], 0.5)
	else:
		p.glow(cos(gl) * rr, sin(gl) * rr, 4.0, C[6], 0.25)

	# 环上眨眼的小星
	Px.cycle(t, D, 4, float(o.seed) + 3.0, func(r: Px.Rng): return r.range(0.35, 0.55), func(age: float, life: float, r: Px.Rng):
		var g := r.range(0.0, TAU)
		var d := r.range(1.02, 1.18)
		var k := sin((age / life) * PI)
		Px.sparkle(p, cos(g) * rr * d, sin(g) * rr * d, 0.8 + 1.6 * k, WHITE, C[6], 0.45 * k))
