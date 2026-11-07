# The plus sign's lit and shaded bevel is adapted from Sprite Fusion's open-source heal (https://www.spritefusion.com/pixel-art-vfx/heal),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# Shared by the holy effects: gold, green and ash ramps, the character's silhouette and recolors, floor ovals,
# feathers of light (drawn, and simulated as they rock and sink) and plus signs.
# Files starting with _ are helpers, not effects.
# port-of: src/fx/holy/_lib.js@fbf39afb15e8ca554c0ea472cf92bbb476b33cee
extends RefCounted

const Px := preload("../../core/px.gd")
const Self := preload("_lib.gd")
const WHITE := Px.WHITE

## Holy gold, dark to bright: a plum shadow, rust, amber, gold, pale gold, cream, white.
const GOLD := ["#3b1d2a", "#7a3a2c", "#c4652e", "#f0a040", "#ffd25e", "#fff0a0", "#fffbe0", "#ffffff"]
## Healing green, warm: deep pine, leaf, spring green, a yellow-green highlight, cream.
const GREEN := ["#0e2a24", "#14472f", "#1d6e3a", "#2f9a45", "#5cc654", "#a0e46c", "#dcffb4", "#ffffff"]
## Ash: the colour of the fallen, a cool grey-violet, dark to light.
const ASH := ["#16131c", "#26222f", "#3a3546", "#524c5e", "#6e6878", "#8c8796"]

# ---- the character

static var SHAPES := {}

## The actor's silhouette as local points, cached per mask: edge (its own rim pixels), out (the 1 px ring just
## outside it), at.call(x, y) (inside?), top and bottom (y of the first row and one past the last).
static func shapeOf(A: Dictionary) -> Dictionary:
	var s: Variant = SHAPES.get(A.mask.id)
	if s != null and s.x == A.x and s.y == A.y:
		return s
	var m: Dictionary = A.mask
	var mw: int = m.w
	var mh: int = m.h
	var data: PackedByteArray = m.data
	var inside := func(i: int, j: int) -> bool: return i >= 0 and j >= 0 and i < mw and j < mh and data[j * mw + i] > 0
	var edge := []
	var out := []
	for j in range(-1, mh + 1):
		for i in range(-1, mw + 1):
			var nb := int(inside.call(i - 1, j)) + int(inside.call(i + 1, j)) + int(inside.call(i, j - 1)) + int(inside.call(i, j + 1))
			if inside.call(i, j):
				if nb < 4:
					edge.append([A.x + i, A.y + j])
			elif nb:
				out.append([A.x + i, A.y + j])
	var ax: int = A.x
	var ay: int = A.y
	s = {"x": A.x, "y": A.y, "edge": edge, "out": out, "top": A.y, "bottom": A.y + mh, "at": func(x: float, y: float) -> bool: return inside.call(floori(x) - ax, floori(y) - ay)}
	SHAPES[A.mask.id] = s
	return s


## Draw the actor's own pixels recolored: fn.call(c, x, y) gives the new color for its pixel c at (x, y), or 0 to
## leave that pixel alone (the character shows through). a: alpha, or a Callable of (x, y).
static func recolor(p: Px.Painter, A: Dictionary, fn: Callable, a: Variant = 1.0) -> void:
	var m: Dictionary = A.mask
	var P: Variant = A.get("pixels")
	var fa := a is Callable
	if not P:
		return
	var nf := fn.get_argument_count()
	var na: int = a.get_argument_count() if fa else 0
	var mw: int = m.w
	var mh: int = m.h
	for j in mh:
		for i in mw:
			var c: int = P[j * mw + i]
			if not c:
				continue
			var x: int = A.x + i
			var y: int = A.y + j
			var n: Variant = Px.call4(fn, nf, c & 0xFFFFFFFF, x, y)
			if n:
				p.dot(x, y, n, Px.call4(a, na, x, y) if fa else a)


## A color mapped onto a ramp by its brightness (a tint that keeps the character's shading).
static func toneOf(R: Array, c: int, lift: float = 0.0) -> int:
	return R[int(Px.clamp(floorf((Px.luma(c) * 1.1 + lift) * R.size()), 0.0, R.size() - 1))]

# ---- floor and ovals

## A 1 px oval (a ring on a tilted plane): centre (cx, cy), radii rx, ry. c and a may be Callables of the angle
## g round it (sin(g) > 0 is the near side). keep.call(g) picks the part to draw.
static func oval(p: Px.Painter, cx: float, cy: float, rx: float, ry: float, c: Variant, a: Variant = 1.0, keep: Variant = null) -> void:
	if rx < 0.5:
		return
	var n := ceilf(maxf(rx, ry) * TAU * 1.5) + 6.0
	var fc := c is Callable
	var fa := a is Callable
	var j := 0
	while j < n:
		var g := (j / n) * TAU
		j += 1
		if keep != null and not keep.call(g):
			continue
		p.dot(cx + cos(g) * rx, cy + sin(g) * ry, c.call(g) if fc else c, a.call(g) if fa else a)

static var FAR := func(g: float) -> bool: return sin(g) < 0.0
static var NEAR := func(g: float) -> bool: return sin(g) >= 0.0

# ---- feathers

## A feather of light from its quill at (x, y) pointing along ang, len px long, with a rounded tip; the
## trailing vane, wid px wide, falls on side (1: clockwise of the shaft, -1: the other way), the leading vane
## is under half that. R: a ramp, dark to bright (6+ steps). a: alpha. hot 0..1 whitens it (a flash). A white
## shaft, a lit leading rim, a warm dark trailing edge that parts it from the next feather, a body that cools
## from cream at the quill to gold, and a tip that thins into light.
static func feather(p: Px.Painter, x: float, y: float, ang: float, len: float, wid: float, R: Array, a: float = 1.0, side: float = 1.0, hot: float = 0.0, quill: float = 0.02) -> void:
	if len < 1.5 or a <= 0.02:
		return
	var n := R.size()
	var ca := cos(ang)
	var sa := sin(ang)
	var x1 := x + ca * len
	var y1 := y + sa * len
	var pad := wid + 1.2
	var h := hot > 0.5
	var edge: int = R[n - 3] if h else R[n - 5]
	var lead: int = WHITE if h else R[n - 2]
	var B: Array = [WHITE, WHITE, R[n - 2]] if h else [R[n - 2], R[n - 3], R[n - 4]]
	p.each(minf(x, x1) - pad, minf(y, y1) - pad, maxf(x, x1) + pad, maxf(y, y1) + pad, func(px: float, py: float, sx: int, sy: int) -> void:
		var dx := px - x
		var dy := py - y
		var u := (dx * ca + dy * sa) / len
		if u < 0.0 or u > 1.05:
			return
		var v := (-dx * sa + dy * ca) * side
		var av := absf(v)
		var w := wid * sqrt(Px.clamp((u - quill) / 0.22)) * sqrt(maxf(0.0, 1.0 - pow(maxf(0.0, (u - 0.55) / 0.47), 2.0)))
		var lim := w * 0.42 if v < 0.0 else w
		var fade := 1.0 if u < 0.72 else 1.0 - (u - 0.72) * 1.6
		if av < 0.5 and u < 0.9:
			p.put(sx, sy, WHITE if u < 0.5 else B[0], a)
			return
		if av > lim + 0.05 or w < 0.5:
			return
		if lim - av < 1.0:
			if v > 0.0:
				p.put(sx, sy, B[2] if u > 0.85 else edge, a * fade)
			else:
				p.put(sx, sy, lead, a)
			return
		if u < 0.72:
			p.put(sx, sy, B[0] if u < 0.38 else B[1], a)
			return
		p.blendPx(sx, sy, B[2], a * fade))


## Loose feathers that are thrown, brake hard, then rock like a pendulum as they sink, tilting with each swing
## and sinking fastest through the bottom of it; on the floor they lie flat and fade.
## add({ x, y (centre), vx, vy, a (angle), len, wid, life, delay, back }); update(dt); draw(p, R, layer).
class Feathers extends RefCounted:
	var R: Px.Rng
	var floor: float
	var list: Array = []
	var count: int:
		get: return list.size()

	func _init(rng: Px.Rng, floor_: float = 0.0) -> void:
		R = rng
		floor = floor_
		list = []

	func add(f: Dictionary) -> void:
		var q := {"vx": 0.0, "vy": 0.0, "a": 0.0, "len": 7.0, "wid": 2.0, "delay": 0.0, "back": false, "side": R.sign(), "ph": R.range(0.0, TAU), "w": R.range(3.2, 4.6), "amp": R.range(6.0, 11.0), "sink": R.range(14.0, 24.0), "va": R.range(-9.0, 9.0), "tilt": R.range(-0.35, 0.35)}
		q.merge(f, true)
		q.max = f.life
		q.age = 0.0
		q.landed = false
		list.append(q)

	func update(dt: float) -> void:
		var i := list.size() - 1
		while i >= 0:
			var f: Dictionary = list[i]
			if f.delay > 0:
				f.delay -= dt
				i -= 1
				continue
			f.life -= dt
			if f.life <= 0:
				list.remove_at(i)
				i -= 1
				continue
			f.age += dt
			if f.landed:
				f.a += (Px.round(f.a / PI) * PI - f.a) * minf(1.0, dt * 10.0)
				i -= 1
				continue
			# the throw: drag kills it fast while it spins
			f.vx -= f.vx * 3.4 * dt
			f.vy -= f.vy * 3.4 * dt
			var s := Px.smooth(0.1, 0.6, f.age)
			var ph: float = f.age * f.w + f.ph
			var c := cos(ph)
			# the flutter: a swing across, a sink that's fastest through the bottom of each swing
			f.x += (f.vx + sin(ph) * f.amp * s * 0.9) * dt
			f.y += (f.vy + f.sink * s * (c * c * 1.5 - 0.2)) * dt
			# it lies along its swing, tipping up at each end
			var rest: float = Px.round(f.a / PI) * PI + f.tilt + sin(ph) * 0.6
			f.a += f.va * dt * (1.0 - s) + (rest - f.a) * minf(1.0, dt * 5.0 * s)
			if f.y >= floor - 0.5:
				f.y = floor - 0.5
				f.landed = true
				f.life = minf(f.life, 0.6)
			i -= 1

	func draw(p: Px.Painter, R_: Array, layer: String = "") -> void:
		for f: Dictionary in list:
			if f.delay > 0 or (layer != "" and ("back" if f.back else "front") != layer):
				continue
			var k: float = f.life / f.max
			var a := minf(minf(1.0, f.life / 0.45), f.age / 0.06)
			var ca := cos(f.a)
			var sa := sin(f.a)
			Self.feather(p, f.x - (ca * f.len) / 2.0, f.y - (sa * f.len) / 2.0, f.a, f.len, f.wid, R_, a, f.side, 1.0 if f.age < 0.06 else 0.0, 0.2)
			p.glow(f.x, f.y, 4.0 + f.len * 0.5, R_[R_.size() - 3], 0.22 * a * (0.4 + 0.6 * k))

# ---- plus signs

## A plus sign of light centred on (x, y): arm length L (1..4) and thickness th (1 or 3): a white heart and
## spine, colored arms lit on the top and left, shaded on the bottom and right. R: a ramp, dark to bright.
static func plus(p: Px.Painter, x: float, y: float, L: float, th: float, R: Array, a: float = 1.0, glint: bool = false) -> void:
	var n := R.size()
	var X := Px.round(x)
	var Y := Px.round(y)
	var w := 1.0 if th > 1.0 else 0.0
	var ins := func(i: float, j: float) -> bool: return (absf(i) <= w and absf(j) <= L) or (absf(j) <= w and absf(i) <= L)
	var j := -L - 1.0
	while j <= L + 1.0:
		var i := -L - 1.0
		while i <= L + 1.0:
			if not ins.call(i, j):
				if w and (ins.call(i - 1.0, j) or ins.call(i + 1.0, j) or ins.call(i, j - 1.0) or ins.call(i, j + 1.0)):
					p.dot(X + i, Y + j, R[maxi(0, n - 6)], a * 0.9)
				i += 1.0
				continue
			var c: int
			if not w:
				c = WHITE if (i == 0.0 and j == 0.0) else (R[n - 3] if absf(i) + absf(j) >= L else R[n - 2])
			elif i == 0.0 and j == 0.0:
				c = WHITE
			elif i == 0.0 or j == 0.0:
				c = R[n - 2] if absf(i) + absf(j) < L else R[n - 3]
			else:
				c = R[n - 3] if (i < 0.0 or j < 0.0) else R[n - 5]
			if glint and ((i == 0.0 and j == -L) or (i == -L and j == 0.0)):
				c = WHITE
			p.dot(X + i, Y + j, c, a)
			i += 1.0
		j += 1.0
