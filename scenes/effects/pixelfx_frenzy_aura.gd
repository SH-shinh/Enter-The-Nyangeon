# 参考 pixelfx status/rage 的心跳节奏、怒气符号、头部蒸汽、应力线与余烬（MIT）。
# 去掉：角色重绘/皮肤泛红/燃烧眼睛（无 actor 剪影）、地面热光与裂纹（按需求不要）。
# 无空白帧：怒气符号 + 红光 + 常驻余烬每帧都在画。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const Lib := preload("res://addons/pixelfx/fx/status/_lib.gd")

static var meta := {
	"name": "Frenzy aura",
	"desc": "Enraged: an anger mark throbs at the temple, steam jets off the head, stress lines flash on each heartbeat and embers rise off the body.",
	"tags": ["status", "rage", "frenzy", "buff", "loop"],
	"size": [80, 80],
	"origin": [40, 64],
	"duration": 1.2,
	"loop": true,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#1a0208", "#4a0612", "#8a0c1c", "#c81828", "#ff3040", "#ff7a7a", "#ffc8c8", "#ffffff"],
		"heat": ["#5a0a0a", "#c8281a", "#ff7a2a", "#ffd27a"],
		"steam": "#f2e8ee",
		"seed": 6,
	},
}

const D := 1.2
const LUB := 0.05
const DUB := 0.29
## 虚拟身体：脚底为原点，头在这个高度
const HEAD_Y := -30.0
const BODY_W := 20.0


static func pulse(t: float, at: float, w: float = 0.06) -> float:
	return exp(-pow((fmod(fmod(t - at, D) + D + D / 2.0, D) - D / 2.0) / w, 2.0))


static func beat(t: float) -> float:
	return pulse(t, LUB) + 0.65 * pulse(t, DUB)


static func since(t: float, at: float) -> float:
	return fmod(fmod(t - at, D) + D, D)


## 怒气符号：四个弧围出一个十字缺口，大小两档随拍切换
static var MARK := [
	Lib.bitmap(["..#.#..", "..#.#..", "##...##", ".......", "##...##", "..#.#..", "..#.#.."]),
	Lib.bitmap(["...#.#...", "...#.#...", "..##.##..", "###...###", ".........", "###...###", "..##.##..", "...#.#...", "...#.#..."]),
]


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var Hh := Px.fit(o.heat, 4)
	var steam := Px.hex(o.steam)
	var b := beat(t)

	# 常驻余烬：从身体两侧升起，保证每一帧都有内容
	Px.cycle(t, D, 9, float(o.seed) + 11.0, func(r): return r.range(0.55, 0.95), func(age: float, life: float, r: Px.Rng):
		var u := age / life
		var side := -1.0 if r.chance(0.5) else 1.0
		var x0 := side * r.range(4.0, BODY_W * 0.5 + 2.0)
		var y := -4.0 - r.range(0.0, 18.0) - age * r.range(34.0, 58.0)
		var drift := sin(age * 7.0 + x0) * 1.2
		Lib.ember(p, x0 + drift, y, u, [Hh[3], Hh[2], Hh[1]], age + x0, 0.85))

	# 怒气符号：随拍在两档之间切换，常驻
	var big := pulse(t, LUB + 0.02, 0.05) > 0.35 or pulse(t, DUB + 0.02, 0.04) > 0.6
	var mx := BODY_W * 0.5 + 1.0
	var my := HEAD_Y
	Lib.icon(p, mx, my, 5, MARK[1 if big else 0], [C[0], C[3], C[4], C[5]])
	p.px(mx - (3.0 if big else 2.0), my - (3.0 if big else 2.0), C[6])
	p.glow(mx, my, 10.0, C[4], 0.35 + 0.45 * b)

	# 应力线：只在拍点闪出
	for anl: Array in [[LUB, 8, 7.0], [DUB, 6, 5.0]]:
		var at: float = anl[0]
		var n: int = anl[1]
		var ln: float = anl[2]
		var age := since(t, at)
		if age > 0.2:
			continue
		var k := age / 0.2
		for i in n:
			var ang := -PI / 2.0 + ((i + 0.5) / n - 0.5) * 4.4
			var r0 := 15.0 + 6.0 * k
			var ca := cos(ang)
			var sa := sin(ang)
			var cy: float = HEAD_Y + 6.0
			var pts := []
			for j in range(0, 4):
				var rr := r0 + (j / 3.0) * ln
				var off := 1.3 if j % 2 else -0.4
				pts.append([ca * rr - sa * off, cy + sa * rr + ca * off])
			p.polyline(pts, func(u): return C[7] if u > 0.66 else (C[5] if u > 0.33 else C[4]), 1.2 - k)
			p.glowLine(pts[0][0], pts[0][1], pts[3][0], pts[3][1], 3.0, C[4], 0.3 * (1.0 - k))

	# 蒸汽：拍点后从头部两侧喷出
	for anp: Array in [[LUB + 0.04, 7, 1.0], [DUB + 0.04, 4, 0.75]]:
		var at: float = anp[0]
		var n: int = anp[1]
		var power: float = anp[2]
		for side: int in [-1, 1]:
			for i in n:
				var age := since(t, at + i * 0.016)
				var life := 0.22 + 0.12 * Px.rand(i, side, 3)
				if age >= life:
					continue
				var u := age / life
				var ang := -PI / 2.0 + side * (0.5 + 0.2 * Px.rand(i, side, 5))
				var sp := (90.0 + 40.0 * Px.rand(i, side, 7)) * power
				var x: float = side * BODY_W * 0.36 + cos(ang) * Lib.travel(sp, 0.0, 7.0, age)
				var y: float = HEAD_Y + sin(ang) * Lib.travel(sp, 0.0, 7.0, age) - 8.0 * age
				var rad := (1.0 + 3.2 * sqrt(u)) * (0.8 + 0.4 * Px.rand(i, side, 9))
				var k := minf(1.0, u * 12.0) * pow(1.0 - u, 2.0)
				p.disc(x, y, rad, steam, 0.85 * k)
				p.disc(x - rad * 0.2, y - rad * 0.25, rad * 0.6, 0xffffffff, 0.75 * k)

	# 头部与胸口红光，随心跳起伏
	p.glow(0.0, HEAD_Y, 28.0, C[4], 0.18 + 0.45 * b)
	p.glow(0.0, HEAD_Y + 12.0, 36.0, C[3], 0.12 + 0.22 * b)
