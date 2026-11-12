# The bolt shape and the way a bolt is inked (a deep halo, a pale body, a white core, light along it) are
# adapted from Sprite Fusion's open-source lightning (https://www.spritefusion.com/pixel-art-vfx/lightning),
# MIT License, Copyright (c) 2026 Hugo Duprez.
#
# Shared by the lightning effects: bolts that fork and thin as they split, inked at the 2x character scale,
# thin crackles, bowed arcs, heat scorch, and trajectories for pure loops.
# port-of: src/fx/lightning/_lib.js@0d41c83b5f154235588d80143f2d4fd7537c4886
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const FIRE_RAMP := Px.FIRE_RAMP
const SMOKE_RAMP := Px.SMOKE_RAMP

## Default palette, dark to bright: deep violet shadow, electric blue, icy white.
const VOLT := ["#120a33", "#2a1b78", "#4630c0", "#5a62f0", "#58a6ff", "#9ed8ff", "#e4f6ff", "#ffffff"]
## Plasma sparks, head to tail: cyan that reads apart from the violet bolt.
const PLASMA := ["#ffffff", "#c8f8ff", "#7ff3ff", "#1ab8e6"]
static var SOOT := Px.hex("#110c16")
static var SOOT2 := Px.hex("#1c1522")


## A bolt from (x0, y0) to (x1, y1): midpoint displacement down to ~3 px segments (jag: how far the first
## midpoint may swing, as a share of the length), with forks that split off along the way, each thinner (w)
## and forking again up to two levels. Returns { paths: [{ pts: [[x, y], ...], w }] }, the trunk first.
static func zigzag(R: Px.Rng, x0: float, y0: float, x1: float, y1: float, jag: float = 0.32, forks: float = 0.35, w: float = 1.0, depth: int = 0) -> Dictionary:
	var out := {"paths": []}
	var L := Px.hypot(x1 - x0, y1 - y0)
	var pts := [[x0, y0], [x1, y1]]
	var off := L * jag
	while pts.size() < 2 + L / 3.0:
		var nxt := [pts[0]]
		for i in pts.size() - 1:
			var ax: float = pts[i][0]
			var ay: float = pts[i][1]
			var bx: float = pts[i + 1][0]
			var by: float = pts[i + 1][1]
			var l := Px.hypot(bx - ax, by - ay)
			if not l:
				l = 1.0
			var o := R.range(-off, off)
			nxt.append([(ax + bx) / 2.0 + (-(by - ay) / l) * o, (ay + by) / 2.0 + ((bx - ax) / l) * o])
			nxt.append([bx, by])
		pts = nxt
		off *= 0.52
	out.paths.append({"pts": pts, "w": w})
	if depth < 2:
		for i in range(2, pts.size() - 3):
			if R.chance(forks / (1 + depth) / maxf(4.0, pts.size() / 6.0)):
				var ax: float = pts[i][0]
				var ay: float = pts[i][1]
				var bx: float = pts[mini(pts.size() - 1, i + 3)][0]
				var by: float = pts[mini(pts.size() - 1, i + 3)][1]
				var a := atan2(by - ay, bx - ax) + R.sign() * R.range(0.35, 0.9)
				var l := (L - (float(i) / pts.size()) * L) * R.range(0.25, 0.55)
				out.paths.append_array(zigzag(R, ax, ay, ax + cos(a) * l, ay + sin(a) * l, jag * 1.1, forks, w * 0.55, depth + 1).paths)
	return out


## A bolt bowed off the straight line by `bow` px at its middle (negative: up for a left-to-right arc).
static func bowed(R: Px.Rng, x0: float, y0: float, x1: float, y1: float, bow: float, jag: float = 0.22, forks: float = 0.4) -> Dictionary:
	var L := Px.hypot(x1 - x0, y1 - y0)
	if not L:
		L = 1.0
	var nx := -(y1 - y0) / L
	var ny := (x1 - x0) / L
	var mx := (x0 + x1) / 2.0 + nx * bow + R.range(-2.0, 2.0)
	var my := (y0 + y1) / 2.0 + ny * bow
	var a := zigzag(R, x0, y0, mx, my, jag, forks)
	var b := zigzag(R, mx, my, x1, y1, jag, forks)
	var paths: Array = [{"pts": a.paths[0].pts + b.paths[0].pts.slice(1), "w": 1.0}]
	paths.append_array(a.paths.slice(1))
	paths.append_array(b.paths.slice(1))
	return {"paths": paths}


## Move every point of a bolt: fn(x, y) => [x, y].
static func bend(b: Dictionary, fn: Callable) -> Dictionary:
	var paths := []
	for q: Dictionary in b.paths:
		var pts := []
		for pt: Array in q.pts:
			pts.append(fn.call(pt[0], pt[1]))
		paths.append({"w": q.w, "pts": pts})
	return {"paths": paths}


# ---- inking. Pixels are gathered in a grid at a level (higher wins), then drawn once each, so a fork's
# halo never covers the trunk's body and overlapping passes cost nothing extra.
const N := 1024
const HALF := 512
static var GRID := _grid()
static var HIT := PackedInt32Array()


static func _grid() -> PackedByteArray:
	var g := PackedByteArray()
	g.resize(N * N)
	return g


static func mark(x: float, y: float, lvl: int) -> void:
	var X := floori(x) + HALF
	var Y := floori(y) + HALF
	if X < 0 or Y < 0 or X >= N or Y >= N:
		return
	var i := Y * N + X
	var v := GRID[i]
	if not v:
		HIT.append(i)
	if lvl > v:
		GRID[i] = lvl


static func stamp(x: float, y: float, r: float, lvl: int) -> void:
	if r <= 0.5:
		mark(Px.round(x), Px.round(y), lvl)
		return
	var r2 := r * r
	for py in range(floori(y - r), ceili(y + r) + 1):
		var dy := py + 0.5 - y
		for px in range(floori(x - r), ceili(x + r) + 1):
			var dx := px + 0.5 - x
			if dx * dx + dy * dy <= r2:
				mark(px, py, lvl)


## Draw what was gathered: level n in cols[n - 1] at alpha alphas[n - 1] (dithered below 1).
static func flush(p: Px.Painter, cols: Array, alphas: Variant) -> void:
	for i in HIT:
		var v := GRID[i]
		GRID[i] = 0
		var x := (i % N) - HALF
		var y := floori(float(i) / N) - HALF
		var a: float = alphas[v - 1] if alphas else 1.0
		if a >= 1.0:
			p.px(x, y, cols[v - 1])
		elif a > 0.0:
			p.dot(x, y, cols[v - 1], a)
	HIT.clear()


static func walk(pts: Array, fn: Callable) -> void:
	for i in pts.size() - 1:
		var ax: float = pts[i][0]
		var ay: float = pts[i][1]
		var bx: float = pts[i + 1][0]
		var by: float = pts[i + 1][1]
		var l := maxf(1.0, Px.hypot(bx - ax, by - ay))
		var d := 0.0
		while d <= l:
			fn.call(ax + ((bx - ax) * d) / l, ay + ((by - ay) * d) / l, i)
			d += 0.5


## A bolt at full power: a deep halo, a pale body, a white core on the trunk, light every few points. k is the
## stroke's brightness (forks drop out below 0.5, the trunk thins below 0.6), s scales the thickness.
## o: { hero (a white frame: the body goes white), light (glow strength), a (alpha), upTo (draw the trunk only
## to this share of its length), core (radius of a thicker white core), minY (no glow above this y) }.
static func stroke(p: Px.Painter, b: Dictionary, k: float, C: Array, s: float = 1.0, o: Dictionary = {}) -> void:
	if k <= 0.02:
		return
	var lk: float = o.light if o.get("light") != null else 0.5
	var core: Variant = o.get("core")
	for q: Dictionary in b.paths:
		var trunk: bool = q.w >= 1.0
		if not trunk and k < 0.5:
			continue
		var rh := (((2.1 if k > 0.6 else 1.6) if trunk else 1.1)) * s
		var rb := (((1.3 if k > 0.6 else 0.8) if trunk else 0.5)) * s
		var pts: Array = q.pts.slice(0, maxi(2, ceili(q.pts.size() * o.upTo))) if (o.has("upTo") and trunk) else q.pts
		walk(pts, func(x, y, _i):
			stamp(x, y, rh, 1)
			stamp(x, y, rb, 3 if trunk else 2)
			if trunk and k > 0.3:
				if core:
					stamp(x, y, core, 4)
				else:
					mark(x, y, 4))
		var i := 0
		while i < pts.size() - 1:
			if not o.has("minY") or pts[i][1] > o.minY:
				p.glow(pts[i][0], pts[i][1], (14.0 if trunk else 7.0) * s, C[4], lk * k * q.w)
			i += 3
	var a: float = o.a if o.get("a") != null else 1.0
	flush(p, [C[3], C[6], C[7], C[7]] if o.get("hero") else [C[2], C[4], C[5], C[7]], [a, a, a, a])


## A thin crackle: a 1 px core (white on the trunk while bright), a 2 px pale body, a dithered halo while k is
## high, light along it. For short arcs that live a frame or two.
static func crackle(p: Px.Painter, b: Dictionary, k: float, C: Array, glowK: float = 0.5, a: float = 1.0) -> void:
	if k <= 0.02:
		return
	for q: Dictionary in b.paths:
		var thick: bool = q.w >= 1.0
		var qw: float = q.w
		walk(q.pts, func(x, y, _i):
			if k > 0.45 and thick:
				for dd in CROSS:
					mark(x + dd[0] * 1.5, y + dd[1] * 1.5, 1)
			if k > 0.25 and (thick or qw > 0.4):
				mark(x + 1.0, y, 2)
				mark(x, y + 1.0, 2)
			mark(x, y, 4 if (thick and k > 0.3) else 3))
		var i := 0
		while i < q.pts.size() - 1:
			p.glow(q.pts[i][0], q.pts[i][1], (9.0 if thick else 5.0) * (0.5 + k * 0.5), C[4], glowK * k * q.w)
			i += 3
	flush(p, [C[3], C[5], C[5], C[7]], [minf(1.0, (k - 0.45) * 1.6) * a, a, a, a])
const CROSS := [[1, 0], [-1, 0], [0, 1], [0, -1]]


## A bolt's trunk as a 1 px line in one color (leaders, afterimages, cooling channels).
static func trace(p: Px.Painter, pts: Array, c: int, a: float = 1.0, from: int = 0, to: Variant = null) -> void:
	var too: int = pts.size() - 1 if to == null else to
	for i in range(maxi(0, from), mini(too, pts.size() - 1)):
		p.line(pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], c, a)


## Heat left on the floor: a flat ellipse, white-hot in the middle cooling through the fire ramp to soot.
## T0 is the heat (1 fresh, 0 cold), fade takes the soot away.
static func scorch(p: Px.Painter, cx: float, cy: float, rx: float, T0: float, fade: float = 1.0, ry: Variant = null) -> void:
	var ryy: float = maxf(2.5, rx * 0.12) if ry == null else ry
	if fade <= 0.0:
		return
	var y := floori(cy)
	while y <= cy + ryy:
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ryy
			var d := sqrt(dx * dx + dy * dy)
			if d > 1.0:
				continue
			var n := Px.rand(x, y, 41)
			var T := T0 * (1.25 - d) - n * 0.35
			if T > 0.06:
				var c: int = FIRE_RAMP[mini(FIRE_RAMP.size() - 1, floori((1.0 - minf(1.0, T)) * (FIRE_RAMP.size() - 1)))]
				p.dot(x, y, c, fade)
				if (x & 3) == 0:
					p.glow(x + 0.5, y, 6.0, c, 0.18 * T * fade)
			else:
				p.dot(x, y, SOOT if d < 0.5 else SOOT2, (1.0 if d < 0.95 - n * 0.3 else 1.0 - d) * fade)
		y += 1


## A heat-ramp color for T (1 white-hot .. 0 cold), or 0 when it's cold.
static func heat(T: float) -> int:
	return FIRE_RAMP[mini(FIRE_RAMP.size() - 1, floori((1.0 - minf(1.0, T)) * (FIRE_RAMP.size() - 1)))] if T > 0.06 else 0


## Where a spark launched at (x, y, vx, vy) is after `age` seconds, stepped like the simulation's SPARK (gravity,
## drag, bouncing on a floor at `floor`), so pure loops get the same physics. Returns [x, y, vx, vy].
static func flight(x: float, y: float, vx: float, vy: float, age: float, opts: Dictionary = {}) -> Array:
	var g: float = opts.get("g", 0.45)
	var drag: float = opts.get("drag", 2.2)
	var fl: float = opts.get("floor", INF)
	var bounce: float = opts.get("bounce", 0.45)
	var dt := 1.0 / 120.0
	var s := 0.0
	while s < age:
		var h := minf(dt, age - s)
		vy += Px.GRAVITY * g * h
		vx -= vx * drag * h
		vy -= vy * drag * h
		var ny := y + vy * h
		x += vx * h
		if vy > 0.0 and y <= fl and ny >= fl:
			vy = -vy * bounce
			vx *= 0.7
			y = fl - 0.25
		else:
			y = ny
		s += dt
	return [x, y, vx, vy]


## A spark drawn the way the simulation draws one (a streak stretched by speed, a hot head, light), for pure loops.
static func spark(p: Px.Painter, x: float, y: float, vx: float, vy: float, k: float, S: Array) -> void:
	var sp := Px.hypot(vx, vy)
	if not sp or is_nan(sp):
		sp = 1.0
	var ux := vx / sp
	var uy := vy / sp
	var head: int = S[0] if k > 0.6 else (S[1] if k > 0.3 else S[2])
	var ln := minf(9.0, 1.0 + sp * 0.022)
	p.line(x - ux * ln, y - uy * ln, x - ux * ln * 0.4, y - uy * ln * 0.4, head if k > 0.5 else S[S.size() - 1])
	p.line(x - ux * ln * 0.45, y - uy * ln * 0.45, x, y, head)
	p.glow(x, y, 3.0, head, 0.45 * k)


## A soft smoke puff at age u (0..1) of its life, drawn like the simulation's SMOKE, for pure loops.
static func puff(p: Px.Painter, x: float, y: float, size: float, u: float, c: int) -> void:
	var k := 1.0 - u
	var r := size * (0.65 + minf(1.0, u * 2.5) * 0.45 + u * 0.4)
	var a := minf(1.0, u * 12.0) * minf(1.0, k * 2.4) * 0.58
	if a <= 0.01:
		return
	var col := Px.mix(c, SMOKE_RAMP[mini(SMOKE_RAMP.size() - 1, floori(u * SMOKE_RAMP.size()))], u)
	p.disc(x, y, r, col, a * 0.45)
	p.disc(x + r * 0.05, y + r * 0.06, r * 0.74, col, a * 0.62)
	if u < 0.5:
		p.disc(x - r * 0.22, y - r * 0.3, r * 0.5, Px.mix(col, Px.hex("#ffffff"), 0.12), a * 0.4 * (1.0 - u * 2.0))


## A seeded generator for frame f of a loop (new shapes every frame, the same shapes every time).
static func frameRng(seed: Variant, f: Variant, salt: Variant = 0) -> Px.Rng:
	return Px.rng(seed, salt, f)
