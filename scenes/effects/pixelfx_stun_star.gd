# 参考 pixelfx status/stunned（MIT）的「头顶星星环」部分：
# 三星 + 两只小鸟绕头（倾斜椭圆环，星星前后穿插、拖 glitter、扫过正面时 flare），
# 外加环外随机 sparkle 与整体暖光。
# 参考库原效果是 actor 效果（带身体姿态 lean/crouch/pose），这里 fork 成 bodyless：
# 不重绘身体、不做姿态，环中心固定在原点，由跟随 FX 按体型缩放并贴到头顶。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const Lib := preload("res://addons/pixelfx/fx/status/_lib.gd")

static var meta := {
	"name": "Stun stars",
	"desc": "Three spinning stars and two little birds circle the head on a tilted ring, ducking behind it and sweeping round in front, trailing glitter.",
	"tags": ["status", "stun", "dizzy", "daze", "stars", "birds", "debuff", "loop"],
	"size": [48, 32],
	"origin": [24, 20],
	"duration": 2.0,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#3a1e0c", "#8a4a12", "#d88a1c", "#f5c030", "#ffe36e", "#fff6c8", "#ffffff"],
		"birds": ["#1a1422", "#6a7fae", "#b8c8e8", "#f4f8ff"],
		"beak": "#ffae35",
		"seed": 2,
	},
}

## bodyless：环中心固定在画布原点，逻辑体型固定 24 宽（由跟随 FX 缩放适配实际体型）。
const ACTOR := {"w": 24.0, "y": 0.0}

static var D: float = meta.duration
const TURNS := 2.0
const N := 5
const STAR7 := ["...#...", "..###..", "#######", ".#####.", "..###..", ".##.##.", ".#...#."]

# 一只朝右的小鸟：身体、头、眼、喙、尾、扇动的翅膀
static func bird(up: bool) -> Callable:
	return func(dx, dy) -> String:
		var x: float = dx + 0.5
		var y: float = dy + 0.5
		if dx == 3 and dy == -2:
			return "e"
		if (dx == 5 or dx == 4) and dy == -1:
			return "b" if dx == 5 else "#"
		var wing := [[-1, -1], [-1, -2], [-2, -2], [-2, -3], [-3, -3], [-3, -4]] if up else [[-1, 1], [-1, 2], [-2, 2], [-2, 3], [0, 1]]
		if wing.any(func(ab): return ab[0] == dx and ab[1] == dy):
			return "w"
		if pow(x / 3.3, 2.0) + pow((y - 0.6) / 1.9, 2.0) <= 1.0 or pow(x - 2.8, 2.0) + pow(y + 1.2, 2.0) <= pow(1.7, 2.0):
			return "#"
		if (dx == -4 and (dy == -1 or dy == 0)) or (dx == -5 and dy == -1):
			return "#"
		return ""

static var BIRD := [true, false].map(func(up): return bird(up))
static var STAR_SHAPE := Lib.starShape(0.44)

static func STAR(s: float, ang: float) -> Callable:
	return Lib.shaped(STAR_SHAPE, s, ang)

# 环：星星在 0/2/4，鸟在 1/3
static func ring(t: float, a: Dictionary) -> Array:
	var cy: float = a.y + 2
	var rx: float = a.w * 0.62
	var ry := 4.5
	return Px.arr(N, func(i: int):
		var th := TAU * ((TURNS * t) / D + i / float(N))
		var s := sin(th)
		return {"i": i, "th": th, "x": cos(th) * rx, "y": cy + s * ry, "near": s >= 0.0, "depth": 0.5 + 0.5 * s, "bird": i % 2 == 1, "rx": rx, "ry": ry, "cy": cy})

static func draw1(p: Px.Painter, t: float, o: Dictionary, layer: String) -> void:
	var C := Px.fit(o.palette, 7)
	var Bd := Px.fit(o.birds, 4)
	var a: Dictionary = ACTOR
	var far := layer == "back"
	var dim := func(c: int) -> int: return Px.mix(c, Bd[0], 0.3) if far else c
	for it: Dictionary in ring(t, a):
		if it.near == far:
			continue
		# 星星身后的环上拖 glitter
		if not it.bird:
			for k in range(1, 13):
				var th: float = it.th - k * 0.085
				var x: float = cos(th) * it.rx
				var y: float = it.cy - 1.0 + sin(th) * it.ry
				if (sin(th) >= 0.0) == far or Px.rand(it.i, k, floorf(((t / D) * TURNS + k * 0.37) * 9.0)) < 0.25:
					continue
				p.dot(x, y, dim.call(C[6] if k < 4 else (C[5] if k < 8 else C[4])), 1.1 - k / 13.0)
				if k < 6:
					p.light(x, y, C[4], 0.3 * (1.0 - k / 6.0))
		if it.bird:
			var up := floori(t * 8.0 + it.i * 0.5) % 2 == 0
			var bob: float = sin((t / D) * TAU * 4.0 + it.i) * 0.7
			var flip: bool = it.near
			var f: Callable = BIRD[0 if up else 1]
			var ins: Callable = (func(dx, dy): return f.call(-dx, dy)) if flip else f
			Lib.icon(p, it.x, it.y - 3.0 + bob, 7, ins, [Bd[0], dim.call(Bd[1]), dim.call(Bd[2]), dim.call(Bd[3])], 1.0, {"e": Bd[0], "b": dim.call(Px.hex(o.beak)), "w": dim.call(Bd[1])})
		else:
			var spin: float = (t / D) * TAU * 3.0 + it.i
			var R := [C[0], dim.call(C[3]), dim.call(C[4]), dim.call(C[5])]
			if it.depth > 0.55:
				Lib.icon(p, it.x, it.y - 1.0, 7, STAR(4.0 + 0.8 * it.depth, spin), R)
			else:
				Lib.icon(p, it.x, it.y - 1.0, 5, Lib.bitmap(STAR7), R)
			p.px(it.x, it.y - 1.0, C[5] if far else C[6])
			p.glow(it.x, it.y - 1.0, 11.0, C[4], 0.24 + 0.3 * it.depth)
			p.glow(it.x, it.y - 1.0, 4.0, C[6], 0.3 * it.depth)
			# 扫过正面（最靠近眼睛）时来一下 flare
			var fr := exp(-pow(atan2(sin(it.th - PI / 2.0), cos(it.th - PI / 2.0)) / 0.32, 2.0))
			if not far and fr > 0.08:
				Px.flare(p, it.x, it.y - 1.0, 9.0 * fr, fr, [C[3], C[4], C[5], C[6]])

static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	draw1(p, t, o, "back")

static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 7)
	var a: Dictionary = ACTOR
	draw1(p, t, o, "front")
	# 环外随机冒出的 sparkle
	Px.cycle(t, D, 14, o.seed + 3, func(r): return r.range(0.25, 0.5), func(age: float, life: float, r: Px.Rng):
		var th: float = r.range(0.0, TAU)
		var u: float = age / life
		var x: float = cos(th) * a.w * r.range(0.45, 0.95)
		var y: float = a.y + 1.0 + sin(th) * 7.0 - r.range(0.0, 9.0)
		var arm := Px.round(r.range(1.0, 2.6) * sin(PI * u))
		if arm < 1.0:
			p.dot(x, y, C[6], sin(PI * u) * 1.4)
		Px.sparkle(p, x, y, arm, C[5], C[4], 0.35 * sin(PI * u)))
	p.glow(0.0, a.y + 1.0, 26.0, C[4], 0.13)
