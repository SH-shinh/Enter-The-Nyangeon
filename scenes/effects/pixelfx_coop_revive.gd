# fork of pixelfx holy/resurrection（MIT，见 third_party/pixelfx-godot/NOTICE）。
# 相对原版：去掉角色本体/光池/光环，只保留光柱 + 羽翼 + 羽毛 + 粒子，并压缩到 0.45s。
# port-of: src/fx/holy/resurrection.js@3e58ca3ab5ef83a5080fa92aa74305a065f927c2
extends "res://addons/pixelfx/core/effect.gd"

const Px := preload("res://addons/pixelfx/core/px.gd")
const Lib := preload("res://addons/pixelfx/fx/holy/_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Coop revive",
	"desc": "Light pours down on the fallen and life climbs back up the body; wings of light unfold, a halo forms, one great wingbeat, then the wings scatter into feathers.",
	"tags": ["holy", "revive", "resurrect", "wings", "halo", "light", "character", "one-shot"],
	"size": [192, 160],
	"origin": [96, 140],
	"duration": 0.45,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"actor": 2,
		"options": {"palette": Lib.GOLD, "ash": Lib.ASH, "seed": 5},
}

static var DOWN := {"turn": 0.9, "crouch": 8, "lean": 6, "hy": 2, "fx": -4, "fy": -10, "bx": 9, "by": -10, "ffx": 8, "fbx": -7}
static var RISEN := {"turn": 1.15, "crouch": -1, "fx": -15, "fy": -33, "bx": 16, "by": -33, "hy": -1, "ffx": -3, "ffy": -5, "fbx": 4, "fby": -5}
static var act := {
	"onBody": false,
	"follow": 0.6,
	"poses": [
		[0, DOWN],
		[0.5, DOWN],
		[0.85, Px.merge(DOWN, {"crouch": 6, "lean": 4, "hy": 1})],
		[1.15, {"turn": 1, "crouch": 2, "fx": -8, "fy": -17, "bx": 9, "by": -17}],
		[1.5, Px.merge(RISEN, {"y": -2})],
		[1.95, Px.merge(RISEN, {"y": -3})],
		[2.1, Px.merge(RISEN, {"y": -2, "crouch": 1, "fy": -37, "by": -37})],
		[2.3, Px.merge(RISEN, {"y": -9, "fx": -15, "fy": -38, "bx": 16, "by": -38})],
		[2.95, Px.merge(RISEN, {"y": -6})],
		[3.8, {"turn": 1, "y": 0, "crouch": 2, "fx": -8, "fy": -17, "bx": 9, "by": -17}],
		[4.3, Px.READY],
		[4.8, Px.READY],
	],
	"dust": [{"t": 3.8, "x": 0, "n": 5}],
}

const TOP := -140.0
# the story: the light pours, life climbs the body, wings and halo, the beat, the wings come apart
const POUR := 0.06
const CL0 := 0.08
const CL1 := 0.13
const W0 := 0.06
const H0 := 0.20
const H1 := 0.24
const B0 := 0.22
const B1 := 0.26
const B2 := 0.28
const B3 := 0.33
const SC := 0.34
const GONE := 0.45
const HX := 0.0
const HY := -47.0
const HRX := 9.5
const HRY := 2.6

# the right wing (the left mirrors it), from its shoulder: the arm folded and spread, then each feather
# [where along the arm 0..1, angle spread, length, width, kind]: 0 primary, 1 secondary, 2 covert
const SHOULDER := [4.0, -20.0]
const ARM_OPEN := [[0.0, 0.0], [7.0, -9.0], [15.0, -19.0], [20.0, -27.0]]
const ARM_FOLD := [[0.0, 0.0], [2.0, -2.0], [3.0, -3.0], [4.0, -3.0]]
const QUILLS := [
	[0.14, 1.35, 11.0, 2.6, 1], [0.26, 1.12, 14.0, 2.8, 1], [0.38, 0.88, 17.0, 3.0, 1], [0.5, 0.62, 19.0, 3.1, 1], [0.62, 0.35, 21.0, 3.2, 1], [0.72, 0.08, 23.0, 3.3, 1],
	[0.8, -0.2, 26.0, 3.4, 0], [0.85, -0.45, 29.0, 3.5, 0], [0.9, -0.72, 31.0, 3.6, 0], [0.95, -1.0, 30.0, 3.6, 0], [1.0, -1.3, 26.0, 3.4, 0],
	[0.22, 1.2, 7.0, 2.2, 2], [0.34, 0.98, 8.0, 2.3, 2], [0.46, 0.75, 9.0, 2.4, 2], [0.58, 0.5, 10.0, 2.5, 2], [0.7, 0.22, 10.0, 2.5, 2], [0.81, -0.1, 11.0, 2.6, 2], [0.92, -0.5, 11.0, 2.6, 2],
]
const FLEX := [1.0, 0.5, 0.3]

static func along(pts: Array, s: float) -> Array:
	var L := 0.0
	var seglen := []
	for i in range(1, pts.size()):
		var sl := Px.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1])
		seglen.append(sl)
		L += sl
	var d := s * L
	for i in seglen.size():
		if d <= seglen[i] or i == seglen.size() - 1:
			var f: float = Px.clamp(d / seglen[i]) if seglen[i] else 0.0
			return [Px.lerp(pts[i][0], pts[i + 1][0], f), Px.lerp(pts[i][1], pts[i + 1][1], f)]
		d -= seglen[i]
	return pts[pts.size() - 1]


# the beat: a slow raise, a hard fast downstroke, a recovery that overshoots a touch
static func beat(t: float) -> float:
	if t < B0:
		return 0.0
	if t < B1:
		return -0.34 * Px.Ease.inOutSine(Px.seg(t, B0, B1))
	if t < B2:
		return Px.lerp(-0.34, 0.66, Px.Ease.inQuad(Px.seg(t, B1, B2)))
	return 0.66 * (1.0 - Px.Ease.outBack(Px.seg(t, B2, B3), 1.3))


var C: Array
var AS: Array
var A: Dictionary
var S: Dictionary
var R: Px.Rng
var WING: Array
var ps: Px.Particles
var lights: Px.Lights
var loose: Lib.Feathers
var rows := {}
var rays: Array
var cores: Array
var motes: Array
var reach: Array
var far: float
var quills: Array
var profile := PackedFloat32Array()
var t := 0.0
var poured := false
var flashed := false
var formed := false
var beaten := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	AS = Px.fit(o.ash, 6)
	A = o.actor
	S = Lib.shapeOf(A)
	R = Px.Rng.new(o.seed)
	WING = [C[2], C[3], C[4], C[5], C[6], WHITE]
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[3]], "haze": C[4]})
	lights = Px.Lights.new()
	loose = Lib.Feathers.new(R, 0.0)
	rows = {}
	for xy: Array in S.edge:
		var y: int = xy[1]
		if not rows.has(y):
			rows[y] = []
		rows[y].append(xy[0])
	# the shaft of light: a few rays of their own width and shimmer
	rays = Px.arr(6, func(i: int): return {"o": -0.75 + i * 0.3 + R.range(-0.08, 0.08), "w": R.range(0.1, 0.2), "b": R.range(0.55, 1.0), "f": R.range(1.5, 3.5), "ph": R.range(0.0, TAU)})
	cores = Px.sort(rays.duplicate(), func(a, b): return b.b - a.b).slice(0, 2)
	motes = Px.arr(34, func(_i): return {"q": R.range(-1.0, 1.0), "y": R.range(0.0, 1.0), "v": R.range(4.0, 11.0), "amp": R.range(0.6, 2.4), "ph": R.range(0.0, TAU), "f": R.range(0.6, 1.4)})
	# each feather opens on its own beat, outer ones last, and comes off at its own time, tips first
	reach = []
	for Q: Array in QUILLS:
		var s: float = Q[0]
		var ang: float = Q[1]
		var len: float = Q[2]
		var b := along(ARM_OPEN, s)
		reach.append(Px.hypot(b[0] + cos(ang) * len, b[1] + sin(ang) * len))
	far = reach.max()
	quills = []
	for i in QUILLS.size():
		var Q: Array = QUILLS[i]
		var s: float = Q[0]
		var kind: int = Q[4]
		var off := func() -> float: return SC + (1.0 - reach[i] / far) * 0.2 + R.range(0.0, 0.04)
		quills.append({"s": s, "ang": Q[1], "len": Q[2], "wid": Q[3], "kind": kind, "fold": 1.45 + (i % 6) * 0.04, "open": 0.06 + (s - 0.8) * 0.45 if kind == 0 else (s * 0.06 if kind == 1 else 0.03 + s * 0.05), "off": [off.call(), off.call()], "gone": [false, false]})
	profile = PackedFloat32Array()
	profile.resize(121)


func climbY(tt: float) -> float:
	return Px.lerp(1.0, S.top - 2.0, Px.Ease.inOutSine(Px.seg(tt, CL0, CL1)))


func shaftK(tt: float) -> float:
	return Px.smooth(0.0, 0.12, tt) * (1.0 - Px.smooth(3.0, 3.75, tt))


func shaftW(tt: float) -> float:
	return Px.lerp(0.4, 1.0, Px.Ease.outCubic(Px.seg(tt, 0.0, 0.6))) * Px.lerp(1.0, 0.12, Px.Ease.inCubic(Px.seg(tt, 2.9, 3.6)))


func halfW(y: float, tt: float) -> float:
	return Px.lerp(15.0, 42.0, (y - TOP) / -TOP) * shaftW(tt)


# the pose of every feather of one wing at time tt: quill base (x, y), angle, length, width, alpha, hot
func wing(tt: float, side: float) -> Dictionary:
	var oa := Px.Ease.outBack(Px.seg(tt, W0, W0 + 0.4), 1.6)
	var rot := beat(tt)
	var om := (beat(tt) - beat(tt - 0.03)) / 0.03
	var arm := []
	for i in ARM_FOLD.size():
		var f: Array = ARM_FOLD[i]
		arm.append([Px.lerp(f[0], ARM_OPEN[i][0], oa), Px.lerp(f[1], ARM_OPEN[i][1], oa)])
	var cr := cos(rot)
	var sr := sin(rot)
	var place := func(xy: Array) -> Array:
		var x: float = xy[0]
		var y: float = xy[1]
		return [side * (SHOULDER[0] + x * cr - y * sr), SHOULDER[1] + x * sr + y * cr]
	var a0 := Px.smooth(W0, W0 + 0.1, tt)
	var out := []
	for i in quills.size():
		var q: Dictionary = quills[i]
		if tt >= q.off[0 if side > 0.0 else 1] + 0.05:
			continue
		var of := Px.Ease.outBack(Px.seg(tt, W0 + q.open, W0 + q.open + 0.42), 2.0)
		var bxy: Array = place.call(along(arm, q.s))
		var ang: float = Px.lerp(q.fold, q.ang, of) + rot - Px.clamp(om * 0.045 * FLEX[q.kind], -0.5, 0.5)
		out.append({"i": i, "q": q, "x": bxy[0], "y": bxy[1], "ang": ang if side > 0.0 else PI - ang, "len": q.len * Px.lerp(0.3, 1.0, of), "wid": q.wid, "a": a0, "hot": 1.0 if (tt < W0 + q.open + 0.07 or tt >= q.off[0 if side > 0.0 else 1]) else 0.0})
	return {"out": out, "arm": arm.map(place)}


func drawWing(p: Px.Painter, side: float) -> void:
	var wg := wing(t, side)
	var out: Array = wg.out
	var arm: Array = wg.arm
	if not out.size():
		return
	var order := Px.sort(out.duplicate(), func(a, b): return b.q.ang - a.q.ang)
	# the lowest feathers first, so each one above lays its warm trailing edge over the next; coverts on top
	for f: Dictionary in order:
		if f.q.kind != 2:
			Lib.feather(p, f.x, f.y, f.ang, f.len, f.wid, WING, f.a, side, f.hot)
	for f: Dictionary in order:
		if f.q.kind == 2:
			Lib.feather(p, f.x, f.y, f.ang, f.len, f.wid, WING, f.a, side, f.hot)
	# the leading edge: a white bone of light with a gold underside
	var k := out.size() / float(quills.size())
	if k > 0.5:
		p.polyline(arm.map(func(xy): return [xy[0], xy[1] + 1.0]), C[5], out[0].a)
		p.polyline(arm, WHITE, out[0].a)
	p.glow(side * 28.0, -36.0, 38.0, C[4], 0.26 * out[0].a * k)
	var g := fmod((t - W0 - 0.45) * 1.3, 1.0)
	if k > 0.9 and t > W0 + 0.45 and g < 0.8:
		var gxy := along(arm, g / 0.8)
		Px.sparkle(p, gxy[0], gxy[1], 2.0 + sin((g / 0.8) * PI) * 2.0, WHITE, C[6], 0.4)
	p.glowLine(arm[0][0], arm[0][1], arm[3][0], arm[3][1], 7.0, C[5], 0.25 * out[0].a * k)
	# the tips of the primaries leave trails of light as they come down
	if t > B1 + 0.03 and t < B2 + 0.14:
		for i: int in [6, 8, 10]:
			var pts := []
			for j in 10:
				var tt := maxf(B1 + 0.01, t - j * 0.012)
				var w: Variant = null
				for f: Dictionary in wing(tt, side).out:
					if f.i == i:
						w = f
						break
				if w:
					pts.append([w.x + cos(w.ang) * (w.len - 1.0), w.y + sin(w.ang) * (w.len - 1.0)])
			var fade := 1.0 - Px.smooth(B2, B2 + 0.14, t)
			for j in range(1, pts.size()):
				p.line(pts[j - 1][0], pts[j - 1][1], pts[j][0], pts[j][1], WHITE if j < 3 else (C[6] if j < 6 else C[4]), fade * (1.1 - j / 10.0))


# profile[i], or NaN past its ends (a JS typed array read out of range is undefined)
func _prof(i: int) -> float:
	return profile[i] if (i >= 0 and i < profile.size()) else NAN


func shaft(p: Px.Painter) -> void:
	var k := shaftK(t)
	if k <= 0.0:
		return
	for i in profile.size():
		var q := (i - 60) / 40.0
		var I := 0.0
		for r: Dictionary in rays:
			var d: float = (q - r.o) / r.w
			I += r.b * exp(-d * d) * (0.72 + 0.28 * sin(t * r.f + r.ph))
		profile[i] = (I * 0.6 + 0.35 * maxf(0.0, 1.0 - q * q)) * Px.smooth(1.25, 0.7, absf(q))
	var front := Px.lerp(TOP, 1.0, Px.Ease.inQuad(Px.seg(t, 0.0, POUR)))
	var w0 := halfW(0.0, t) * 1.3
	p.each(-w0 - 1.0, TOP, w0 + 1.0, minf(front, 0.5), func(x: float, y: float, sx: int, sy: int) -> void:
		var w := halfW(y, t)
		var q := x / w
		if q < -1.5 or q > 1.5:
			return
		var I := _prof(Px.roundi(q * 40.0) + 60) * k * (0.75 + 0.25 * Px.smooth(TOP, 0.0, y)) * Px.smooth(front, front - 10.0, y)
		if I <= 0.01:
			return
		p.blendPx(sx, sy, C[6], I * 0.32)
		p.add(sx, sy, C[4], I * 0.38))
	# the brightest rays show as fine lines, light running down them
	for r: Dictionary in cores:
		var sh: float = 0.75 + 0.25 * sin(t * r.f + r.ph)
		var y := TOP
		while y < minf(front, 0.0):
			var pulse: float = 0.5 + 0.5 * sin(y * 0.13 - t * 11.0 + r.ph)
			p.dot(r.o * halfW(y, t), y, WHITE if pulse > 0.8 else C[6], k * sh * (0.15 + 0.55 * pulse) * Px.smooth(front, front - 10.0, y))
			y += 1.0
	# the head of the pour
	if t < POUR + 0.05 and front > TOP + 14.0:
		var fy := minf(front, 0.0)
		p.glow(0.0, fy, 14.0, C[5], 0.7 * k)
		for dy in range(-6, 1):
			p.dot(0.0, fy + dy, WHITE if dy > -3 else C[6], 1.0 + dy / 7.0)
	# dust motes lit where they cross a ray
	for m: Dictionary in motes:
		var y := TOP + fmod(fmod(m.y * -TOP + t * m.v, -TOP) + -TOP, -TOP)
		if y > front:
			continue
		var w := halfW(y, t)
		var x: float = m.q * w + sin(t * m.f + m.ph) * m.amp
		var I := _prof(Px.roundi((x / w) * 40.0) + 60) * k
		if I < 0.25:
			continue
		p.dot(x, y, WHITE if I > 0.75 else (C[6] if I > 0.5 else C[5]), minf(1.0, I * 1.4))
		p.light(x, y, C[5], I * 0.5)


func pool(p: Px.Painter, back: bool) -> void:
	return
	var k := shaftK(t) * Px.smooth(POUR - 0.05, POUR + 0.1, t)
	var w := halfW(0.0, t) * 1.25
	if k <= 0.0:
		return
	if back:
		p.glow(0.0, -2.0, w * 1.6, C[4], 0.3 * k)
		return
	# the floor catches the light: a bright line, and a pool fading into the stone in front
	for y in 4:
		var x := floorf(-w)
		while x <= w:
			var u := Px.hypot(x / w, y / 4.0)
			if u >= 1.0:
				x += 1.0
				continue
			var a := k * (sqrt(1.0 - u) * 1.2 if y == 0 else (1.0 - u) * 0.9)
			p.dot(x, y, ((C[5] if y else WHITE) if u < 0.3 else (C[5] if u < 0.6 else (C[4] if u < 0.85 else C[3]))), a)
			x += 1.0


func halo(p: Px.Painter) -> void:
	return
	var form := Px.Ease.outCubic(Px.seg(t, H0, H1))
	var k := 1.0 - Px.smooth(3.35, 3.9, t)
	if form <= 0.0 or k <= 0.0:
		return
	var white := t >= H1 and t < H1 + 0.06
	var gl := (t - H1) * 4.2 + PI / 2.0
	var n := 96.0
	for j in int(n):
		var g := (j / n) * TAU
		var fromFront := absf(fmod(fmod(g - PI / 2.0 + PI, TAU) + TAU, TAU) - PI)
		if fromFront > form * PI + 0.02:
			continue
		var x := HX + cos(g) * HRX * (0.9 + 0.1 * form)
		var y := HY + sin(g) * HRY
		var near := sin(g) >= 0.0
		var dg := absf(fmod(fmod(g - gl + PI, TAU) + TAU, TAU) - PI)
		var hot := white or dg < 0.22 or fromFront > form * PI - 0.3
		if near:
			p.dot(x, y, WHITE if hot else C[6], k)
			p.dot(x, y + 1.0, C[6] if hot else C[4], k)
		else:
			p.dot(x, y, C[6] if hot else C[5], k * 0.9)
	p.glow(HX, HY, 20.0, C[4], 0.4 * k * form)
	p.glow(HX, HY + 1.0, 9.0, WHITE, 0.2 * k * form)
	var gx := HX + cos(gl) * HRX
	var gy := HY + sin(gl) * HRY
	if t > H1 and sin(gl) > 0.2:
		Px.sparkle(p, gx, gy + 0.5, 2.0 + 2.0 * sin(gl), C[6], C[4], 0.35 * k)
	if t >= H1 and t < H1 + 0.3:
		Px.sparkle(p, HX, HY + HRY + 0.5, 7.0 * (1.0 - (t - H1) / 0.3), WHITE, C[5], 0.6)


func body(p: Px.Painter) -> void:
	return
	if t >= CL1 + 0.6:
		return
	var Ly := climbY(t)
	if t < CL1:
		var CC := C
		var ASh := AS
		Lib.recolor(p, A, func(c: int, x: float, y: float) -> int:
			var d := y - Ly
			if d < -0.5:
				return Lib.toneOf(ASh, c)
			if d < 0.5:
				return WHITE
			if d < 1.5:
				return CC[6]
			var k := exp(-(d - 1.5) / 4.0) * 0.7
			return Px.mix(c, CC[5], k) if k > 0.08 else 0)
		# the outline catches the light where the glow has been
		for xy: Array in S.out:
			var x: float = xy[0]
			var y: float = xy[1]
			var d := y - Ly
			if d < -0.5 or d > 12.0:
				continue
			p.dot(x, y, WHITE if d < 1.0 else (C[5] if d < 5.0 else C[4]), 1.0 if d < 1.0 else 1.1 - d / 12.0)
		if t > CL0:
			p.glow(0.0, Ly, 26.0, C[4], 0.5)
			p.glow(0.0, Ly, 8.0, WHITE, 0.3)
			p.glow(0.0, -18.0, 36.0, C[5], 0.16 * Px.seg(t, CL0, CL1))
		return
	# the hero frame: the body flashes white, then cools through gold back to itself
	var u := t - CL1
	var CC := C
	Lib.recolor(p, A, func(c: int) -> int: return WHITE if u < 0.06 else (Px.mix(c, CC[5], 0.55 * pow(1.0 - u / 0.45, 2.0)) if u < 0.45 else 0))
	if u < 0.25:
		for xy: Array in S.out:
			p.dot(xy[0], xy[1], WHITE if u < 0.08 else C[5], 1.0 - u / 0.25)


func update(dt: float) -> void:
	t += dt
	# light streaks pour down the shaft, faster as they fall
	if t > 0.05 and t < 2.9 and R.chance(0.16):
		var q := R.range(-0.9, 0.9)
		var y := TOP + R.range(8.0, 24.0)
		var v0 := R.range(50.0, 90.0)
		var life := log(1.0 + (3.0 * (-y - 2.0)) / v0) / 3.0
		ps.spawn(P.STREAK, q * halfW(y, t), y, q * 2.0, v0, life, C[6] if R.chance(0.5) else C[5])
	if t > 0.3 and t < 2.8 and R.chance(0.05):
		ps.spawn(P.STAR, R.range(-1.0, 1.0) * halfW(-30.0, t), -R.range(4.0, 90.0), R.range(-3.0, 3.0), R.range(-4.0, 6.0), R.range(0.4, 0.8), C[6] if R.chance(0.5) else WHITE, R.range(0.6, 1.8))
	if not poured and t >= POUR:
		poured = true
		lights.add(0.0, -12.0, 42.0, C[5], 0.9, 0.4)
		lights.add(0.0, -6.0, 16.0, WHITE, 0.6, 0.1)
		for i in 14:
			ps.spawn(P.STAR, R.range(-18.0, 18.0), -R.range(0.0, 6.0), R.range(-20.0, 20.0), -R.range(10.0, 50.0), R.range(0.5, 1.1), WHITE if R.chance(0.5) else C[6], R.range(0.6, 2.2))
		for i in 10:
			var a := -PI / 2.0 + R.range(-1.2, 1.2)
			var sp := R.range(60.0, 150.0)
			ps.spawn(P.SPARK, R.range(-3.0, 3.0), -1.0, cos(a) * sp, sin(a) * sp, R.range(0.25, 0.5))
	# life climbs the body: bits of light peel off the rim at the front
	if false and t > CL0 and t < CL1:
		var Ly := Px.round(climbY(t))
		for y: float in [Ly, Ly + 1.0]:
			var xs: Variant = rows.get(int(y))
			if not xs or not R.chance(0.35):
				continue
			var x: float = R.pick(xs)
			var s := Px.sign(x + 0.5)
			ps.spawn(P.MOTE if R.chance(0.6) else P.STAR, x + s, y, s * R.range(8.0, 30.0), -R.range(15.0, 45.0), R.range(0.35, 0.7), C[6] if R.chance(0.5) else C[5], R.range(0.5, 1.1))
	if false and not flashed and t >= CL1:
		flashed = true
		lights.add(0.0, -24.0, 64.0, C[5], 0.7, 0.5)
		lights.add(0.0, -30.0, 28.0, WHITE, 0.7, 0.1)
		for i in 18:
			var a := R.range(0.0, TAU)
			var sp := R.range(30.0, 110.0)
			ps.spawn(P.STAR, cos(a) * 6.0, -24.0 + sin(a) * 12.0, cos(a) * sp, sin(a) * sp * 0.7 - 20.0, R.range(0.4, 0.9), WHITE if R.chance(0.5) else C[6], R.range(0.6, 2.0))
	# motes spiral in to make the halo
	if false and t > H0 - 0.2 and t < H0 + 0.1 and R.chance(0.6):
		var g := R.range(0.0, TAU)
		var D := R.range(14.0, 24.0)
		var x := HX + cos(g) * D
		var y := HY + sin(g) * D * 0.5
		var tx := HX + cos(g + 0.6) * HRX
		var ty := HY + sin(g + 0.6) * HRY
		var T := R.range(0.16, 0.24)
		var l := Px.hypot(tx - x, ty - y)
		if not l:
			l = 1.0
		var v := (l * 3.0) / (exp(3.0 * T) - 1.0)
		ps.spawn(P.STREAK, x, y, ((tx - x) / l) * v, ((ty - y) / l) * v, T, C[6] if R.chance(0.5) else C[5])
	if false and not formed and t >= H1:
		formed = true
		lights.add(HX, HY, 30.0, C[6], 0.8, 0.3)
	# the wings burst open with a scatter of light
	if t > W0 and t < W0 + 0.35 and R.chance(0.5):
		for side: float in [-1.0, 1.0]:
			var f: Variant = R.pick(wing(t, side).out)
			if f:
				ps.spawn(P.STAR, f.x + cos(f.ang) * f.len, f.y + sin(f.ang) * f.len, side * R.range(5.0, 25.0), -R.range(5.0, 25.0), R.range(0.3, 0.6), WHITE if R.chance(0.5) else C[6], R.range(0.6, 1.6))
	# while the wings hold, light twinkles on the tips and motes lift off them
	if t > W0 + 0.45 and t < SC:
		for side: float in [-1.0, 1.0]:
			if R.chance(0.045):
				var f: Variant = R.pick(wing(t, side).out.filter(func(w): return w.q.kind == 0))
				if f:
					ps.spawn(P.STAR, f.x + cos(f.ang) * (f.len - 2.0), f.y + sin(f.ang) * (f.len - 2.0), 0.0, -R.range(2.0, 8.0), R.range(0.3, 0.6), WHITE if R.chance(0.5) else C[6], R.range(1.0, 2.4))
			if R.chance(0.03):
				var f: Variant = R.pick(wing(t, side).out)
				if f:
					ps.spawn(P.EMBER, f.x + cos(f.ang) * f.len * 0.7, f.y + sin(f.ang) * f.len * 0.7, R.range(-8.0, 8.0), -R.range(8.0, 25.0), R.range(0.6, 1.1), C[5])
	# the downstroke: a gust along the floor, light flung off the tips, a few feathers shaken loose
	if not beaten and t >= B2 - 0.03:
		beaten = true
		for side: float in [-1.0, 1.0]:
			lights.add(side * 30.0, -34.0, 46.0, C[5], 0.6, 0.4)
			# the gust skims out along the floor as streaks of lit dust
			for i in 7:
				ps.spawn(P.MOTE, side * R.range(8.0, 22.0), -R.range(1.0, 4.0), side * R.range(90.0, 160.0), -R.range(0.0, 8.0), R.range(0.25, 0.45), C[6] if R.chance(0.5) else C[5], R.range(0.6, 1.0))
			for f: Dictionary in wing(t, side).out:
				if f.q.kind == 0:
					var tx: float = f.x + cos(f.ang) * f.len
					var ty: float = f.y + sin(f.ang) * f.len
					ps.spawn(P.SPARK, tx, ty, side * R.range(30.0, 90.0), R.range(60.0, 160.0), R.range(0.3, 0.6))
			for i in 3:
				var f: Variant = R.pick(wing(t, side).out.filter(func(w): return w.q.kind == 1))
				if f:
					loose.add({"x": f.x + cos(f.ang) * f.len * 0.6, "y": f.y + sin(f.ang) * f.len * 0.6, "vx": side * R.range(20.0, 70.0), "vy": R.range(10.0, 50.0), "a": f.ang, "len": R.range(9.0, 12.0), "wid": R.range(2.2, 2.8), "life": R.range(1.2, 1.6), "side": side})
	# the wings come apart, tips first: each feather flashes and breaks into small ones and motes
	for side: float in [-1.0, 1.0]:
		var si := 0 if side > 0.0 else 1
		for q: Dictionary in quills:
			if q.gone[si] or t < q.off[si]:
				continue
			q.gone[si] = true
			var f: Variant = null
			for w: Dictionary in wing(q.off[si] - 0.001, side).out:
				if is_same(w.q, q):
					f = w
					break
			if not f:
				continue
			var ca: float = cos(f.ang)
			var sa: float = sin(f.ang)
			var n := 0 if q.kind == 2 else 1
			for j in n:
				var u := 0.55
				var x: float = f.x + ca * f.len * u
				var y: float = f.y + sa * f.len * u
				var ox := x - side * 4.0
				var oy := y + 20.0
				var l := Px.hypot(ox, oy)
				if not l:
					l = 1.0
				var sp := R.range(60.0, 150.0)
				loose.add({"x": x, "y": y, "vx": (ox / l) * sp + R.range(-15.0, 15.0), "vy": (oy / l) * sp * 0.5 - R.range(20.0, 50.0), "a": f.ang + R.range(-0.4, 0.4), "len": R.range(9.0, 12.0), "wid": R.range(2.2, 2.8), "life": R.range(1.0, 1.45), "side": side, "back": R.chance(0.35)})
			for j in 2:
				ps.spawn(P.EMBER, f.x + ca * f.len * R.range(0.3, 1.0), f.y + sa * f.len * R.range(0.3, 1.0), R.range(-15.0, 15.0), -R.range(10.0, 40.0), R.range(0.6, 1.1), C[5])
			if R.chance(0.6):
				ps.spawn(P.STAR, f.x + ca * f.len, f.y + sa * f.len, 0.0, -R.range(5.0, 15.0), R.range(0.3, 0.6), WHITE, R.range(1.0, 2.0))
	# the halo melts into rising motes
	if false and t > 3.35 and t < 3.75 and R.chance(0.4):
		var g := R.range(0.0, TAU)
		ps.spawn(P.EMBER, HX + cos(g) * HRX, HY + sin(g) * HRY, R.range(-6.0, 6.0), -R.range(10.0, 25.0), R.range(0.5, 0.9), C[5])
	ps.update(dt)
	lights.update(dt)
	loose.update(dt)


func drawBack(p: Px.Painter) -> void:
	shaft(p)
	pool(p, true)
	if t > POUR and t < POUR + 0.4:
		Px.band(p, 0.0, 0.0, 4.0 + 32.0 * Px.Ease.outCubic(Px.seg(t, POUR, POUR + 0.4)), 0.18, 2.5 * (1.0 - Px.seg(t, POUR, POUR + 0.4)) + 0.5, 1.1 - Px.seg(t, POUR, POUR + 0.4), C.slice(3), Lib.FAR, t < POUR + 0.06)
	for side: float in [-1.0, 1.0]:
		drawWing(p, side)
	loose.draw(p, WING, "back")
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	pool(p, false)
	if t > POUR and t < POUR + 0.4:
		Px.band(p, 0.0, 0.0, 4.0 + 32.0 * Px.Ease.outCubic(Px.seg(t, POUR, POUR + 0.4)), 0.18, 2.5 * (1.0 - Px.seg(t, POUR, POUR + 0.4)) + 0.5, 1.1 - Px.seg(t, POUR, POUR + 0.4), C.slice(3), Lib.NEAR, t < POUR + 0.06)
	body(p)
	# the downstroke sends a ripple of light out along the floor
	if t > B2 - 0.03 and t < B2 + 0.45:
		var u := Px.seg(t, B2 - 0.03, B2 + 0.45)
		var fx := 10.0 + 70.0 * Px.Ease.outCubic(u)
		for s: float in [-1.0, 1.0]:
			for d in 12:
				p.dot(s * (fx - d), 0.0, WHITE if d < 2 else (C[6] if d < 5 else C[4]), (1.0 - u) * (1.0 - d / 12.0) * 1.3)
	# the wings light the character from behind
	var wk := Px.smooth(W0, W0 + 0.2, t) * (1.0 - Px.smooth(SC, SC + 0.3, t))
	if wk > 0.0:
		for xy: Array in S.out:
			if xy[1] < -8:
				p.light(xy[0], xy[1], C[5], 0.55 * wk)
		p.glow(0.0, -34.0, 76.0, C[4], 0.14 * wk)
	halo(p)
	if t >= CL1 and t < CL1 + 0.22:
		Px.flare(p, 0.0, S.top - 1.0, 22.0 * (1.0 - (t - CL1) / 0.22), 1.0 - (t - CL1) / 0.22, C.slice(3))
	loose.draw(p, WING, "front")
	ps.draw(p, "front")
	lights.draw(p)
