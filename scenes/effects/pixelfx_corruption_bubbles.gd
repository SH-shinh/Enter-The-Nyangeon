# 参考 pixelfx nature/toxic-puddle 的冒泡（MIT）：暗色圆顶 + 紫光透出 + 高光，破裂时扩散环 + 溅点。
# 每个泡泡在**自己的循环开始时**随机取一次位置，落在半径 R_MAX 的圆盘内（圆盘均匀采样），
# 并夹到 R_MAX - rmax - 2，保证连同光晕都不会超出画布。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Corruption bubbles",
	"desc": "Glossy bubbles dome up out of the corruption and pop, throwing a ring and a spatter.",
	"tags": ["corruption", "bubbles", "ground", "loop"],
	"size": [116, 116],
	"origin": [58, 58],
	"duration": 2.4,
	"loop": true,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#0b0614", "#1a0b2e", "#2c1250", "#4a1f8a", "#6d2dff", "#9a6bff", "#c9a6ff", "#f0e6ff"],
		"seed": 2,
	},
}

const D := 2.4
## 与现有 Bubbles 粒子发射盒 38×38 的内切圆对齐
const R_MAX := 36.0


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var seed := float(o.seed)
	Px.cycle(t, D, 14, seed, func(g): return g.range(2.0, 3.0), func(age: float, _life: float, R: Px.Rng):
		var rmax := R.range(3.0, 4.0)
		var ang := R.range(0.0, TAU)
		var rad := minf(R_MAX * sqrt(R.next()), R_MAX - rmax - 2.0)
		var x := cos(ang) * rad
		var y := sin(ang) * rad
		var swell := R.range(1.0, 1.6)
		if age < swell:
			var k := age / swell
			var st := Px.smooth(0.65, 1.0, k)
			var gr := Px.Ease.outCubic(minf(1.0, k * 1.3))
			var rx := rmax * gr * (1.0 - 0.18 * st)
			var ry := rmax * gr * (1.0 + 0.5 * st)
			var X := Px.round(x)
			var Y := Px.round(y)
			var inner := 0.35 + 0.65 * k
			for j in range(-ceili(ry) - 1, 1):
				for i in range(-ceili(rx) - 1, ceili(rx) + 2):
					var dd := Px.hypot(i / maxf(0.6, rx), j / maxf(0.6, ry))
					if dd > 1.1:
						continue
					var c: int
					if dd > 0.9:
						c = C[0]
					elif dd < 0.55 * inner and j > -ry * 0.75:
						c = C[7] if dd < 0.3 * inner else C[6]
					elif dd < 0.8 * inner:
						c = C[5]
					else:
						c = C[2] if j < -ry * 0.5 else C[3]
					p.px(X + i, Y + j, c)
			if rx > 1.8:
				var a := 3.5
				while a < 4.7:
					p.px(X + cos(a) * rx * 0.68, Y + sin(a) * ry * 0.68, C[7] if a < 3.9 else (C[6] if a < 4.3 else C[3]))
					a += 0.16
			if rx > 1.2:
				p.px(X - Px.round(rx * 0.35), Y - Px.round(ry * 0.62), WHITE)
				p.px(X - Px.round(rx * 0.35) + 1.0, Y - Px.round(ry * 0.62), C[7])
			p.glow(x, y - ry * 0.5, 8.0 + rx * 1.0, C[6], (0.30 + 0.40 * st) * gr)
			return
		var e := age - swell
		# 破裂：扩散环 + 溅点
		if e < 0.3:
			var k := e / 0.3
			var rr := 2.0 + 10.0 * Px.Ease.outCubic(k)
			var a2 := 0.0
			while a2 < TAU:
				p.dot(x + cos(a2) * rr, y + sin(a2) * rr, WHITE if k < 0.4 else (C[7] if k < 0.7 else C[6]), (1.0 - k) * 1.2)
				a2 += 0.5 / maxf(rr, 1.0)
			p.glowRing(x, y, rr, 2.0, C[6], 0.35 * (1.0 - k))
			if e < 0.1:
				p.glow(x, y - 2.0, 14.0, C[6], 0.6 * (1.0 - e / 0.1))
		for j in 6:
			var vx := (Px.rand(j, seed, Px.round(x * 10.0)) - 0.5) * 60.0
			var vy := -20.0 - Px.rand(j, seed + 3.0, Px.round(x * 10.0)) * 30.0
			var dxy := Px.fly(x, y, vx, vy, e, 300.0)
			if e < 0.5:
				p.px(dxy[0], dxy[1], C[1])
				p.px(dxy[0], dxy[1] - 1.0, C[6]))
