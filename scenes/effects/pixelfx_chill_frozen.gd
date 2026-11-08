# 参考 pixelfx status/frozen（MIT）的非 actor 元素：
# ① 上方细雪（向中间收窄） ② 身上冰晶闪烁 ③ 一次向左右爆开、再抛物线下落的碎晶
# ④ 底部独立的一组垂直下落粒子。不重绘身体、不画壳/霜蕨/地面。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Chill frozen",
	"desc": "Snow narrows toward the body, ice glints on it, chips burst once to the sides in arcs and a separate drizzle falls at the feet.",
	"tags": ["ice", "chill", "frozen", "status", "one-shot"],
	"size": [64, 72],
	"origin": [32, 64],
	"duration": 0.95,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"],
		"seed": 4,
	},
}

const D := 0.95
const BURST_AT := 0.14
const BURST_G := 300.0


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	if t >= D:
		return
	var C := Px.fit(o.palette, 8)
	var seed := float(o.seed)

	# ---- ① 细雪：头顶较宽，落到身体时向中间收窄
	Px.cycle(t, D, 14, seed, func(r: Px.Rng): return r.range(0.75, 1.0), func(age: float, life: float, r: Px.Rng):
		var u := age / life
		if u > 0.95:
			return
		var x0 := r.range(4.0, 14.0) * (1.0 if r.next() < 0.5 else -1.0)
		var x := x0 * (1.0 - 0.55 * u) + sin(age * 3.0 + x0) * 1.5
		var y := -46.0 + 52.0 * u
		var c: int = WHITE if r.next() < 0.4 else C[6]
		p.px(x, y, c)
		p.light(x, y, C[5], 0.3))

	# ---- ② 身上冰晶闪烁（躯干/头肩几个固定点轮流亮）
	for i in 5:
		var x := -8.0 + float(i) * 4.0 + Px.rand(i, 21) * 2.0
		var y := -30.0 + Px.rand(i, 22) * 22.0
		var period := 0.35 + Px.rand(i, 23) * 0.25
		var ph := fmod(t + Px.rand(i, 24) * period, period) / period
		if ph > 0.28:
			continue
		var k := sin(ph / 0.28 * PI)
		p.px(x, y, WHITE if k > 0.6 else C[6])
		if k > 0.85:
			p.px(x - 1.0, y, C[6])
			p.px(x + 1.0, y, C[6])
			p.px(x, y - 1.0, C[6])
			p.px(x, y + 1.0, C[6])
		p.light(x, y, C[5], 0.7 * k)

	# ---- ③ 一次向左右爆开：vx 恒定、重力向下 → 抛物线；末段按像素逐格剥落
	var age := t - BURST_AT
	if age >= 0.0 and age < 0.45:
		var dissolve := clampf((age - 0.22) / 0.20, 0.0, 1.0)
		for i in 6:
			var side := -1.0 if i % 2 == 0 else 1.0
			# 溅射距离比 v4 近 50%
			var vx := side * (27.0 + Px.rand(i, 41) * 15.0)
			var vy := -(10.0 + Px.rand(i, 42) * 15.0)
			var x0 := side * (6.0 + Px.rand(i, 43) * 4.0)
			var y0 := -18.0 + Px.rand(i, 44) * 10.0
			var x := x0 + vx * age
			var y := y0 + vy * age + 0.5 * BURST_G * age * age
			if y > 6.0:
				continue
			var bx := Px.round(x)
			var by := Px.round(y)
			# 2×2 碎块：按确定性哈希阈值逐格消失 + 调色板降级
			for dy in 2:
				for dx in 2:
					var px_x := bx + float(dx)
					var px_y := by + float(dy)
					if Px.rand(int(px_x) * 13 + i, int(px_y) * 7 + i, 71) < dissolve:
						continue
					var c: int = C[6]
					if dissolve >= 0.75:
						c = C[4]
					elif dissolve >= 0.4:
						c = C[5]
					elif i % 3 == 0 and dx == 0 and dy == 0:
						c = WHITE
					p.px(px_x, px_y, c)
			if dissolve < 0.6:
				p.px(x - vx * 0.012, y - vy * 0.012, C[5])
				p.light(x, y, C[5], 0.45 * (1.0 - dissolve / 0.6))

	# ---- ④ 底部一组：垂直慢速下落，和左右爆开的不是同一批
	for i in 5:
		var t0 := 0.05 + float(i) * 0.06
		var fa := t - t0
		if fa < 0.0 or fa > 0.55:
			continue
		var x := -7.0 + float(i) * 3.5 + Px.rand(i, 51) * 1.0
		var y := -6.0 + (25.0 + Px.rand(i, 52) * 20.0) * fa
		if y > 4.0:
			continue
		var a2 := clampf(1.0 - fa / 0.55, 0.0, 1.0)
		p.px(x, y, C[5] if a2 < 0.7 else C[6])
		p.px(x, y - 1.0, C[4])
