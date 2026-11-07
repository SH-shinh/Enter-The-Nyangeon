# Shared by the status effects (files starting with _ are helpers, not effects): the character's shape, noise
# that loops, and the toolkit's flame, smoke and ember particles drawn from their age alone, so loops stay seamless.
# The flame tongue, flame puff, smoke and ember recipes are
# adapted from Sprite Fusion's open-source fire (https://www.spritefusion.com/pixel-art-vfx/fire),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# The shaded, outlined icons are
# adapted from Sprite Fusion's open-source heal (https://www.spritefusion.com/pixel-art-vfx/heal),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/status/_lib.js@107093a6662c32009aed9882956163caf35a185d
extends RefCounted

const Px := preload("../../core/px.gd")
const WHITE := Px.WHITE

static var SHAPES := {}

## The character's shape, worked out once per mask, in mask space (0, 0 = its top-left): `on.call(x, y)`, `body`
## ([x, y] of every pixel), `up` (pixels with nothing above them: where flames stand), `side` ([x, y, dir] of
## pixels open to the left (-1) or right (1)), `outline` ([x, y, nx, ny]: empty cells touching it, with the
## outward normal), `top` (each column's first row, -1 if empty) and `rows` ([left, right] of each row).
static func shape(a: Dictionary) -> Dictionary:
	var m: Dictionary = a.mask
	var s: Variant = SHAPES.get(m.id)
	if s != null:
		return s
	var w: int = m.w
	var h: int = m.h
	var data: PackedByteArray = m.data
	var on := func(x, y) -> bool: return x >= 0 and y >= 0 and x < w and y < h and data[int(y) * w + int(x)] > 0
	var body := []
	var up := []
	var side := []
	var outline := []
	var top := []
	var rows := []
	for x in w:
		var y := 0
		while y < h and not on.call(x, y):
			y += 1
		top.append(y if y < h else -1)
	for y in h:
		var l := -1
		var r := -1
		for x in w:
			if not on.call(x, y):
				continue
			if l < 0:
				l = x
			r = x
			body.append([x, y])
			if not on.call(x, y - 1):
				up.append([x, y])
			if not on.call(x - 1, y):
				side.append([x, y, -1])
			if not on.call(x + 1, y):
				side.append([x, y, 1])
		rows.append([l, r])
	for y in range(-1, h + 1):
		for x in range(-1, w + 1):
			if on.call(x, y):
				continue
			var nx := 0
			var ny := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if on.call(x + dx, y + dy):
						nx -= dx
						ny -= dy
			if on.call(x - 1, y) or on.call(x + 1, y) or on.call(x, y - 1) or on.call(x, y + 1):
				var l := Px.hypot(nx, ny)
				if not l:
					l = 1.0
				outline.append([x, y, nx / l, ny / l])
	s = {"w": w, "h": h, "on": on, "body": body, "up": up, "side": side, "outline": outline, "top": top, "rows": rows}
	SHAPES[m.id] = s
	return s


## The character's own color at mask pixel (x, y), or a mid grey for a mask without pixels. (Unsigned, like the
## JS Uint32Array read; 0 where JS reads past the array.)
static func colorAt(a: Dictionary, x: int, y: int) -> int:
	var i: int = y * a.mask.w + x
	if a.get("pixels"):
		var PX: PackedInt32Array = a.pixels
		return (PX[i] & 0xFFFFFFFF) if (i >= 0 and i < PX.size()) else 0
	var data: PackedByteArray = a.mask.data
	return (0xff6b6b6b if data[i] else 0) if (i >= 0 and i < data.size()) else 0


## 1D value noise in [-1, 1] whose lattice wraps every P cells.
static func wnoise(x: float, P: float, seed: Variant = 0) -> float:
	var i := floorf(x)
	var f := x - i
	var u := f * f * (3.0 - 2.0 * f)
	var a := Px.rand(Px.wrap(i, P), seed)
	var b := Px.rand(Px.wrap(i + 1.0, P), seed)
	return (a + (b - a) * u) * 2.0 - 1.0


## Noise of time t that repeats every D seconds, about f wiggles a second; off slides along it (ripples).
static func tnoise(t: float, D: float, f: float, seed: Variant = 0, off: float = 0.0) -> float:
	var P := maxf(2.0, Px.round(f * D))
	return wnoise((t / D) * P + off, P, seed)


## How far something has moved after age a, launched at speed v under acceleration g with linear drag d.
static func travel(v: float, g: float, d: float, a: float) -> float:
	return (g / d) * a + ((v - g / d) * (1.0 - exp(-d * a))) / d if d > 0.0 else v * a + 0.5 * g * a * a


# A tongue's nested layers: [width, height, ramp step (0 brightest)]: a deep rim, orange, yellow, a white heart.
const LAYERS := [[1.0, 1.0, 6], [0.76, 0.86, 4], [0.54, 0.68, 2], [0.3, 0.42, 0]]


## A flame tongue standing on (x, y): h tall, w half-wide at its root, its tip swept sx px sideways, filled in
## nested layers from F (bright to dark, 9 steps). Rows ripple with noise that loops every D seconds (seed n).
static func tongue(p: Px.Painter, x: float, y: float, h: float, w: float, sx: float, F: Array, t: float, D: float, n: float, layers: Array = LAYERS) -> void:
	if h < 1.0:
		return
	for L: Array in layers:
		var lw: float = L[0]
		var lh: float = L[1]
		var ri: int = L[2]
		if ri == 0 and h < 4.0:
			continue
		var H := h * lh
		var col: int = F[ri]
		var r := 0
		while r <= H:
			var u := r / maxf(1.0, H)
			var half := w * lw * pow(1.0 - u, 0.85) * minf(1.0, (r + 1.5) / 3.5) + tnoise(t, D, 9.0, n, r * 0.45) * 0.5
			if half < 0.3:
				r += 1
				continue
			var cx := x + sx * u * u * lh + tnoise(t, D, 4.0, n + 7.0, r * 0.2) * u * 1.1
			for px in range(Px.roundi(cx - half), Px.roundi(cx + half) + 1):
				p.px(px, Px.round(y - r), col)
			r += 1


## A ball of flame at age u (0..1) of its life, radius size, cooling down F (bright to dark) as it rises.
static func flame(p: Px.Painter, x: float, y: float, size: float, u: float, F: Array, heatSeed: float = 0.0) -> void:
	var n := F.size()
	var k := 1.0 - u
	var heat := minf(0.999, pow(u, 0.62) + heatSeed * 0.1)
	var idx := mini(n - 2, floori(heat * (n - 1)))
	var r := size * (0.55 + 0.45 * minf(1.0, u * 7.0)) * (1.0 - u * 0.55)
	var c: int = F[idx]
	if idx >= n - 2:
		p.disc(x, y, r, c, minf(1.0, k * 3.0) * 0.85)
		return
	p.circle(x, y, r, F[mini(n - 1, idx + 2)])
	p.circle(x - r * 0.16, y - r * 0.22, r * 0.78, c)
	if r > 1.6:
		p.circle(x, y - r * 0.9, r * 0.42, c)
	if idx <= 3 and r > 1.8:
		p.circle(x - r * 0.28, y - r * 0.34, r * 0.36, F[maxi(0, idx - 1)])
	if idx < 6:
		p.glow(x, y, r * 2.4 + 2.0, c, 0.18 * k)


static func rampAt(r: Array, t: float) -> int:
	return r[mini(r.size() - 1, maxi(0, floori(t * r.size())))]


## A puff of smoke at age u (0..1): three soft discs (a body, a denser core sitting low, a lit cap while young),
## swelling and thinning, tinted col and walking down the smoke ramp. warm (a color) lights its underside.
static func smoke(p: Px.Painter, x: float, y: float, size: float, u: float, col: int, k: float = 1.0, warm: int = 0) -> void:
	var r := size * (0.65 + minf(1.0, u * 2.5) * 0.45 + u * 0.4)
	var a := minf(1.0, u * 12.0) * minf(1.0, (1.0 - u) * 2.4) * 0.58 * k
	if a <= 0.01:
		return
	var c: int = Px.mix(col, rampAt(Px.SMOKE_RAMP, u), u) if col else rampAt(Px.SMOKE_RAMP, u * 1.05)
	p.disc(x, y, r, c, a * 0.45)
	p.disc(x + r * 0.05, y + r * 0.06, r * 0.74, c, a * 0.62)
	if warm and u < 0.6:
		p.disc(x + r * 0.1, y + r * 0.3, r * 0.56, Px.mix(c, warm, 0.5), a * 0.7 * (1.0 - u / 0.6))
	if u < 0.5:
		p.disc(x - r * 0.22, y - r * 0.3, r * 0.5, Px.mix(c, WHITE, 0.12), a * 0.4 * (1.0 - u * 2.0))


## An ember at age u: hot and flickering, cooling to a dim red that blinks out. E is [hot, warm, cool].
static func ember(p: Px.Painter, x: float, y: float, u: float, E: Array, ph: float, k: float = 1.0) -> void:
	var left := 1.0 - u
	if left < 0.22 and sin(ph * 40.0) < 0.0:
		return
	var c: int = ((E[0] if sin(ph * 22.0) > -0.2 else E[1]) if left > 0.5 else (E[1] if left > 0.22 else E[2]))
	p.px(x, y, c)
	p.glow(x, y, 3.0, c, 0.32 * left * k)


## A flat, translucent bank of haze centred on (x, y), rx by ry, thinning to nothing at its edge.
static func haze(p: Px.Painter, x: float, y: float, rx: float, ry: float, col: int, a: float) -> void:
	if a <= 0.01 or rx < 0.5 or ry < 0.5:
		return
	for py in range(floori(y - ry), ceili(y + ry) + 1):
		for px in range(floori(x - rx), ceili(x + rx) + 1):
			var dx := (px + 0.5 - x) / rx
			var dy := (py + 0.5 - y) / ry
			var d := dx * dx + dy * dy
			if d < 1.0:
				p.blend(px, py, col, a * (1.0 - d))


## A shape from a bitmap (rows of strings, "." empty), centred on (0, 0), scaled up by whole k, mirrored if flip:
## returns inside.call(dx, dy) giving the bitmap's character there (or "").
static func bitmap(rows: Array, k: float = 1.0, flip: bool = false) -> Callable:
	var h := rows.size()
	var w: int = String(rows[0]).length()
	var ox := floorf((w * k) / 2.0)
	var oy := floorf((h * k) / 2.0)
	return func(dx, dy) -> String:
		var bx := floori((dx + ox) / k)
		var by := floori((dy + oy) / k)
		if bx < 0 or by < 0 or bx >= w or by >= h:
			return ""
		if flip:
			bx = w - 1 - bx
		var c: String = String(rows[by])[bx]
		return "" if c == "." else c


## A little shaded pixel icon at (x, y): every cell where inside.call(dx, dy) is truthy, within ext of the centre,
## filled from R = [outline, shadow, body, light] (lit on its top and left edges, shaded on the bottom and right,
## ringed by the outline) and recoloured where inside returns a character listed in paint ({ e: eyeColor, ... }).
## a fades it.
static func icon(p: Px.Painter, x: float, y: float, ext: int, inside: Callable, R: Array, a: float = 1.0, paint: Variant = null) -> void:
	var X := Px.round(x)
	var Y := Px.round(y)
	var at := func(dx, dy) -> bool: return true if inside.call(dx, dy) else false
	for dy in range(-ext - 1, ext + 2):
		for dx in range(-ext - 1, ext + 2):
			var ch: Variant = inside.call(dx, dy)
			var c: Variant
			if ch:
				if paint != null and paint.has(ch):
					c = paint[ch]
				else:
					var top: bool = not at.call(dx, dy - 1)
					var left: bool = not at.call(dx - 1, dy)
					var bottom: bool = not at.call(dx, dy + 1)
					var right: bool = not at.call(dx + 1, dy)
					c = R[3] if (top or left) else (R[1] if (bottom or right) else R[2])
			elif R[0] and (at.call(dx - 1, dy) or at.call(dx + 1, dy) or at.call(dx, dy - 1) or at.call(dx, dy + 1)):
				c = R[0]
			else:
				continue
			p.dot(X + dx, Y + dy, c, a)


## inside.call(dx, dy) for a shape given in its own unit space by f.call(u, v), rotated by ang and scaled by s px.
static func shaped(f: Callable, s: float, ang: float = 0.0) -> Callable:
	var c := cos(ang)
	var n := sin(ang)
	return func(dx, dy) -> String:
		var x: float = dx + 0.5
		var y: float = dy + 0.5
		return "#" if f.call((x * c + y * n) / s, (-x * n + y * c) / s) else ""


## A five-pointed star in unit space (points at radius 1, inner corners at r0).
static func starShape(r0: float = 0.45) -> Callable:
	return func(u: float, v: float) -> bool:
		var a := atan2(v, u) + PI / 2.0
		var d := Px.hypot(u, v)
		var seg := (2.0 * PI) / 5.0
		var k := 1.0 - absf(fmod(fmod(a, seg) + seg, seg) - seg / 2.0) / (seg / 2.0)  # 0 at a point, 1 between two
		return d <= 1.0 - (1.0 - r0) * pow(k, 0.8)


## A heart in unit space (two lobes and a point, about 2 wide and 2 tall, centred).
static var heartShape := func(u: float, v: float) -> bool:
	return pow(u + 0.5, 2.0) + pow(v + 0.32, 2.0) <= pow(0.55, 2.0) or pow(u - 0.5, 2.0) + pow(v + 0.32, 2.0) <= pow(0.55, 2.0) or (v >= -0.32 and v <= 1.0 and absf(u) <= 1.04 * pow(1.0 - (v + 0.32) / 1.32, 0.75))

static var EYES := {}

## The character's eyes, if it has any we can find: small blobs of very dark pixels (with any white beside them)
## inside the upper part of the body, surrounded by it. [{ x0, x1, y0, y1, px: [[x, y]...], skin }] in mask
## space, left to right; skin is the colour round them, to paint them shut with. [] when nothing looks like eyes.
static func eyes(a: Dictionary) -> Array:
	var list: Variant = EYES.get(a.mask.id)
	if list != null:
		return list
	# a body that says where its eyes would go: a blank head still needs somewhere to go pink, burn or shut
	if a.get("eyes") != null:
		list = []
		for xy: Array in a.eyes:
			var x: int = xy[0]
			var y: int = xy[1]
			list.append({"x0": x, "x1": x, "y0": y, "y1": y + 1, "px": [[x, y], [x, y + 1]], "skin": colorAt(a, x, y)})
		EYES[a.mask.id] = list
		return list
	var S := shape(a)
	var W: int = S.w
	var Sh: int = S.h
	var on: Callable = S.on
	var col := func(x, y) -> int: return colorAt(a, x, y) if on.call(x, y) else 0
	var dark := func(x, y) -> bool: return on.call(x, y) and y < Sh * 0.4 and Px.luma(col.call(x, y)) < 0.15 and on.call(x - 1, y) and on.call(x + 1, y) and on.call(x, y - 1) and on.call(x, y + 1)
	var seen := {}
	list = []
	for b0: Array in S.body:
		var x0: int = b0[0]
		var y0: int = b0[1]
		if seen.has(y0 * W + x0) or not dark.call(x0, y0):
			continue
		var px := []
		var q := [[x0, y0]]
		seen[y0 * W + x0] = true
		while q.size():
			var cur: Array = q.pop_back()
			var x: int = cur[0]
			var y: int = cur[1]
			px.append([x, y])
			for dd: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx: int = x + dd[0]
				var ny: int = y + dd[1]
				var k := ny * W + nx
				if seen.has(k) or not (dark.call(nx, ny) or (on.call(nx, ny) and Px.luma(col.call(nx, ny)) > 0.95)):
					continue
				seen[k] = true
				q.append([nx, ny])
		if px.size() < 2 or px.size() > 14:
			continue
		var xs := px.map(func(pp): return pp[0])
		var ys := px.map(func(pp): return pp[1])
		var counts := {}
		var e := {"x0": xs.min(), "x1": xs.max(), "y0": ys.min(), "y1": ys.max(), "px": px}
		for pp: Array in px:
			var x: int = pp[0]
			var y: int = pp[1]
			for dd: Array in [[1, 0], [-1, 0], [0, 1], [0, -1], [2, 0], [-2, 0]]:
				var dx: int = dd[0]
				var dy: int = dd[1]
				var c: int = col.call(x + dx, y + dy)
				var l := Px.luma(c)
				if c and l > 0.5 and l < 0.95 and not px.any(func(p2): return p2[0] == x + dx and p2[1] == y + dy):
					counts[c] = counts.get(c, 0) + 1
		var pairs := []
		for c in counts:
			pairs.append([c, counts[c]])
		Px.sort(pairs, func(p1, q1): return q1[1] - p1[1])
		e.skin = pairs[0][0] if pairs.size() else null
		if e.skin and e.x1 - e.x0 <= 4 and e.y1 - e.y0 <= 5:
			list.append(e)
	Px.sort(list, func(p1, q1): return p1.x0 - q1.x0)
	if list.size() > 2:
		list = []
	EYES[a.mask.id] = list
	return list
