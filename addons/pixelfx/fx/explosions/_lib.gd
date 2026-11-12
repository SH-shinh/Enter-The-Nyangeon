# Shared by the explosions. Not an effect (the leading _ keeps the tools away).
# The fire balls, rocks and scorch are adapted from Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/explosions/_lib.js@5fef53c22ad77b63afd0cfe30da073b820670484
extends RefCounted

const Px := preload("../../core/px.gd")
const Self := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const WHITE := Px.WHITE

static var OUTLINE := Px.hex("#1a1422")
static var SOOT := Px.hex("#0d0a12")
static var SOOT2 := Px.hex("#17121d")


## Stone colors from one body color: a lit face, the body, a shaded face, and the dust it makes.
static func stone(c: Variant) -> Dictionary:
	var h := Px.hex(c)
	return {"light": Px.mix(Px.scale(h, 1.35), WHITE, 0.08), "body": h, "shade": Px.scale(h, 0.64), "dust": Px.mix(Px.scale(h, 1.2), Px.rgb(150, 140, 150), 0.3)}


## A 9-step fire ramp, white-hot down to smouldering (the shape of FIRE_RAMP), from an 8-step palette (dark to bright).
static func fireRamp(F: Array) -> Array:
	return [F[7], F[6], F[5], F[4], F[3], F[2], F[1], Px.mix(F[1], F[0], 0.5), F[0]]


## One FIRE particle drawn in the fire ramp FR: a darker rim, a lit core, a tongue on top, a hot heart.
static func fireBall(p: Px.Painter, q: Dictionary, FR: Array) -> void:
	var k: float = q.life / q.max
	var age := 1.0 - k
	var n := FR.size()
	var x: float = q.x
	var y: float = q.y
	var heat := minf(0.999, pow(age, 0.62) + fmod(q.seed, 1.0) * 0.1)
	var idx := mini(n - 2, floori(heat * (n - 1)))
	var r: float = q.size * (0.55 + 0.45 * minf(1.0, age * 7.0)) * (1.0 - age * 0.55)
	var c: int = FR[idx]
	if idx >= n - 2:
		p.disc(x, y, r, c, minf(1.0, k * 3.0) * 0.85)
		return
	# the hottest puffs get a rim a step darker still, so a mass of them reads as separate balls
	p.circle(x, y, r, FR[mini(n - 1, idx + (3 if idx <= 2 else 2))])
	p.circle(x - r * 0.16, y - r * 0.22, r * 0.78, c)
	if r > 1.6:
		p.circle(x, y - r * 0.9, r * 0.42, c)
	if idx <= 3 and r > 1.8:
		p.circle(x - r * 0.28, y - r * 0.34, r * 0.36, FR[maxi(0, idx - 1)])
	if idx < 6:
		p.glow(x, y, r * 2.4 + 2.0, c, 0.18 * k)


## A particle system's layer ("back" or "front") with its FIRE puffs in the fire ramp FR, so a palette recolors them.
static func drawPs(p: Px.Painter, ps: Px.Particles, layer: String, FR: Array) -> void:
	var all := ps.list
	var fires := []
	var rest := []
	for q in all:
		if q.k == P.FIRE:
			fires.append(q)
		else:
			rest.append(q)
	var back := layer == "back"
	if not back:
		for q in fires:
			if q.delay <= 0.0 and not (q.flag & PF.BACK):
				fireBall(p, q, FR)
	ps.list = rest
	ps.draw(p, layer)
	ps.list = all
	if back:
		for q in fires:
			if q.delay <= 0.0 and q.flag & PF.BACK:
				fireBall(p, q, FR)


const LIFTS := {P.SMOKE: true, P.DUST: true, P.FIRE: true, P.EMBER: true, P.VAPOUR: true}


## An updraft column at x: smoke, dust, fire and embers below `top` and within w of the axis are carried up
## (up px/s²) and squeezed toward it; near the floor (within `low` px) they're drawn in from as far as `reach`:
## the afterwinds that feed a blast's column. k scales it all.
static func draft(ps: Px.Particles, dt: float, o: Dictionary) -> void:
	var x: float = o.get("x", 0.0)
	var top: float = o.get("top", -INF)
	var w: float = o.get("w", 12.0)
	var up: float = o.get("up", 150.0)
	var squeeze: float = o.get("squeeze", 4.0)
	var pull: float = o.get("pull", 0.0)
	var low: float = o.get("low", 10.0)
	var reach: float = o.get("reach", 100.0)
	var k: float = o.get("k", 1.0)
	if k <= 0.0:
		return
	for q in ps.list:
		if q.delay > 0.0 or not LIFTS.has(q.k) or q.y < top:
			continue
		var dx: float = q.x - x
		var ax := absf(dx)
		var u := ax / w
		if u < 1.0:
			var f := (1.0 - u * u) * k
			q.vy -= up * f * dt
			q.vx -= dx * squeeze * f * dt
		if pull and q.y > -low and ax > w * 0.4 and ax < reach:
			q.vx -= Px.sign(dx) * pull * k * (1.0 - ax / reach) * dt


## Drop particles that leave the box (local px), so nothing is drawn past the canvas.
static func cull(ps: Px.Particles, x0: float, y0: float, x1: float, y1: float) -> void:
	var L := ps.list
	var i := L.size() - 1
	while i >= 0:
		var q: Dictionary = L[i]
		if q.x < x0 or q.x > x1 or q.y < y0 or q.y > y1:
			L.remove_at(i)
		i -= 1


const SOFT := {P.SMOKE: true, P.DUST: true, P.VAPOUR: true}


## Soft particles (smoke, dust, vapour) fade out over w px as they near the sides x0, x1 and go before they reach
## them; y1, a bottom edge, gets a thin w of 6 (keep things off it by design).
static func fadeEdges(ps: Px.Particles, x0: float, x1: float, w: float = 30.0, y1: float = INF) -> void:
	var L := ps.list
	var i := L.size() - 1
	while i >= 0:
		var q: Dictionary = L[i]
		if not SOFT.has(q.k):
			i -= 1
			continue
		var r: float = q.size * 1.65
		var e := minf((minf(q.x - x0, x1 - q.x) - r) / w, (y1 - q.y - r) / 6.0)
		if e <= 0.0:
			L.remove_at(i)
		elif e < 1.0:
			q.life = minf(q.life, q.max * 0.42 * e)
		i -= 1


## A soft pool of light, an ellipse rx by ry at (x, y): light falling on the floor (keep ry small, it's perspective).
static func pool(p: Px.Painter, x: float, y: float, rx: float, ry: float, c: int, k: float) -> void:
	if k <= 0.004 or rx < 1.0 or ry < 0.5:
		return
	p.shade(x - rx, y - ry, x + rx, y + ry, func(px: float, py: float, out):
		var dx := (px - x) / rx
		var dy := (py - y) / ry
		var d := dx * dx + dy * dy
		if d >= 1.0:
			return
		var f := 1.0 - sqrt(d)
		out.l = c
		out.k = f * f * k)


## A translucent ellipse (blended, never dithered): c and a may be functions of d (0 centre .. 1 rim).
static func haze(p: Px.Painter, x: float, y: float, rx: float, ry: float, c: Variant, a: Variant) -> void:
	if rx < 0.5 or ry < 0.5:
		return
	var fc := c is Callable
	var fa := a is Callable
	p.each(x - rx, y - ry, x + rx, y + ry, func(lx: float, ly: float, sx: int, sy: int):
		var dx := (lx - x) / rx
		var dy := (ly - y) / ry
		var d2 := dx * dx + dy * dy
		if d2 > 1.0:
			return
		var d := sqrt(d2)
		p.blendPx(sx, sy, c.call(d) if fc else c, a.call(d) if fa else a))


## Heat for a scorch, from a fire ramp (bright to dark) down to cinders.
static func heatRamp(FR: Array) -> Array:
	return FR.slice(0, 8) + [Px.mix(FR[8], SOOT, 0.3), Px.mix(FR[8], SOOT, 0.65)]


## The floor under a blast: a burn that spreads out in a blink, glows white-hot and cools through the heat ramp
## HR to soot over `cool` seconds; a few cracks hold their glow twice as long. rows deep, fade 0..1.
static func scorch(p: Px.Painter, HR: Array, t: float, rx0: float, cool: float, fade: float, rows: float = 3.0) -> void:
	if fade <= 0.0:
		return
	var rx := rx0 * minf(1.0, t / 0.08)
	var ry := rows + 1.5
	var n := HR.size()
	var y := 0
	while y < rows:
		for x in range(floori(-rx), ceili(rx) + 1):
			var dx := (x + 0.5) / rx
			var dy := (y + 0.5) / ry
			var d := sqrt(dx * dx + dy * dy)
			if d > 1.0:
				continue
			var k := Px.rand(x * 31 + y, 3)
			var T := pow(Px.clamp(1.0 - t / cool), 1.4) * (1.25 - d) - k * 0.35
			var crack := pow(Px.clamp(1.0 - t / (cool * 2.0)), 1.2) * (1.15 - d) * 0.8 if (k > 0.88 and d < 0.85) else 0.0
			var H := maxf(T, crack)
			if H > 0.06:
				var c: int = HR[mini(n - 1, floori((1.0 - minf(1.0, H)) * (n - 1)))]
				p.dot(x, y, c, fade)
				if (x & 3) == 0 or crack > T:
					p.glow(x + 0.5, y, 6.0, c, 0.18 * H * fade)
			else:
				p.dot(x, y, SOOT if d < 0.5 else SOOT2, (1.0 if d < 0.95 - k * 0.3 else 1.0 - d) * fade)
		y += 1


## A rock (a Bits CHUNK): a lit side, a shaded side and an outline, turning as it spins. b.heat (0..1) makes
## it molten: its heart and shaded side glow through the fire ramp FR and it gives off light, cooling to stone.
static func rock(p: Px.Painter, b: Dictionary, st: Dictionary, FR: Array) -> void:
	var r: float = 0.6 + b.s * 0.75
	var fade := minf(1.0, b.life / 0.5)
	var lx: float = cos(b.a) * r * 0.4
	var ly: float = sin(b.a) * r * 0.4
	var heat: float = b.heat if b.get("heat") != null else 0.0
	var bx: float = b.x
	var by: float = b.y
	p.shade(bx - r - 1.0, by - r - 1.0, bx + r + 1.0, by + r + 1.0, func(x: float, y: float, out):
		var dx := x - bx
		var dy := y - by
		var d := Px.hypot(dx * 1.15, dy)
		if d > r + 0.9:
			return null
		out.a = fade
		if d > r:
			return OUTLINE
		var lit := dx * lx + dy * ly
		if heat > 0.08:
			var g := heat * (1.1 - d / (r + 0.5)) + (heat * 0.45 if lit > 0.3 else 0.0)
			if g > 0.5:
				return FR[1 if g > 1.0 else (2 if g > 0.8 else (3 if g > 0.62 else 4))]
			if g > 0.32:
				return FR[5]
		return st.light if lit < -0.4 else (st.shade if lit > 0.6 else st.body))
	if heat > 0.05:
		p.glow(bx, by, r * 2.0 + 3.0, FR[3], 0.32 * heat * fade)


## Light hugging the upper half of a circle of radius R at (x, y) (a dome's shock), falling off over width w.
## box [x0, y0, x1, y1] (local) keeps it inside a canvas.
static func glowDome(p: Px.Painter, x: float, y: float, R: float, w: float, c: int, k: float, box: Array = [-INF, -INF, INF, INF]) -> void:
	if k <= 0.004 or w < 1.0:
		return
	p.shade(maxf(box[0], x - R - w), maxf(box[1], y - R - w), minf(box[2], x + R + w), minf(box[3], y + 0.5), func(px: float, py: float, out):
		var d := absf(Px.hypot(px - x, py - y) - R) / w
		if d >= 1.0:
			return
		out.l = c
		out.k = (1.0 - d) * (1.0 - d) * k)


## A burning thing's trail: pts [{ x, y, t }] (oldest first) at time t, drawn as a ribbon that is fire near the
## head (fire ramp FR) and swells into thin smoke behind (smoke ramp SM, light to dark) over life seconds.
static func trail(p: Px.Painter, pts: Array, t: float, FR: Array, SM: Array, life: float = 0.5, w: float = 1.0, heat: float = 1.0) -> void:
	var lx := NAN
	var ly := NAN
	var i := pts.size() - 1
	while i >= 0:
		var q: Dictionary = pts[i]
		i -= 1
		var age: float = (t - q.t) / life
		if age >= 1.0:
			break
		if Px.hypot(q.x - lx, q.y - ly) < 1.6:
			continue
		lx = q.x
		ly = q.y
		var r := w * (0.7 + age * 2.6)
		if age < 0.12 * heat:
			p.circle(q.x, q.y - age * 6.0, r * 0.8, FR[3 if age < 0.05 else 5])
		else:
			p.disc(q.x, q.y - age * 6.0, r, SM[mini(SM.size() - 1, 1 + floori(age * 3.0))], 0.55 * (1.0 - age))


## Draw a particle system's GRIT as dirt in flight: fast bits stretch into short streaks (a darker tail, the bit at
## the head), slow ones are the usual 1 or 2 px chips. The rest of the system draws as usual. layer as in draw.
static func drawDirt(p: Px.Painter, ps: Px.Particles, layer: String) -> void:
	var all := ps.list
	var grit := []
	var rest := []
	for q in all:
		if q.k == P.GRIT:
			grit.append(q)
		else:
			rest.append(q)
	ps.list = rest
	ps.draw(p, layer)
	ps.list = all
	if layer == "back":
		return
	for q in grit:
		if q.delay > 0.0:
			continue
		var k: float = q.life / q.max
		var sp := Px.hypot(q.vx, q.vy)
		if k < 0.25 and k * 4.0 < 0.5:
			continue
		if sp > 140.0:
			var L := minf(5.0, sp * 0.012)
			var ux: float = q.vx / sp
			var uy: float = q.vy / sp
			var col: int = q.col
			p.line(q.x - ux * L, q.y - uy * L, q.x, q.y, func(u: float): return Px.scale(col, 0.7) if u < 0.5 else col)
		else:
			p.px(q.x, q.y, q.col)
			if q.size >= 2.0:
				p.px(q.x + 1.0, q.y, q.col)
				p.px(q.x, q.y + 1.0, Px.scale(q.col, 0.8))
				p.px(q.x + 1.0, q.y + 1.0, Px.scale(q.col, 0.7))


## A crater in the floor at x: a dark pit (an ellipse in perspective) with its far wall lit, dirt heaped in a lip on
## either side, and loose earth scattered round it. E: an earth ramp (dark to bright, 5+ steps); r: half-width;
## k: 0..1 how far it has opened; a: alpha (fade it out).
static func crater(p: Px.Painter, E: Array, x: float, r: float, k: float, a: float = 1.0) -> void:
	if k <= 0.0 or a <= 0.0:
		return
	var n := E.size()
	var rx := r * k
	var ry := maxf(1.5, r * 0.17 * k)
	for py in range(-1, ceili(ry) + 2):
		for px in range(floori(-rx - 1.0), ceili(rx + 1.0) + 1):
			var dx := (px + 0.5) / rx
			var dy := (py + 0.5 - ry * 0.35) / ry
			var d := sqrt(dx * dx + dy * dy)
			if d > 1.08:
				continue
			# the pit: darkest at its far side under the lit rim, the near wall a step lighter
			var c: int = (E[n - 2] if dy < 0.0 else E[2]) if d > 0.92 else (E[0] if dy < -0.2 else (E[1] if dy < 0.35 else E[2]))
			p.dot(x + px, py, c, a)
	# the lip: dirt heaped up either side, lit on top, and a scatter of loose earth
	for s: int in [-1, 1]:
		for i in 9:
			var u := i / 8.0
			var h := Px.round(sin(PI * u) * 2.2 * k + (1.0 if Px.rand(i, 3 if s > 0 else 4) < 0.4 else 0.0) * k)
			var hx := x + s * (rx * 0.82 + u * r * 0.55)
			var j := 0
			while j <= h:
				p.dot(hx, -j, E[n - 2] if j == h else (E[3] if j == h - 1 else E[2]), a)
				j += 1
	for i in 26:
		var s := -1.0 if Px.rand(i, 7) < 0.5 else 1.0
		var d := rx * (1.05 + Px.rand(i, 8) * 1.4)
		var y := Px.round(Px.rand(i, 9) * 3.0) - 1.0
		if Px.rand(i, 10) < k:
			p.dot(x + s * d, y, E[3] if Px.rand(i, 11) < 0.5 else E[2], a)


## A hemisphere of white-hot air on the floor at x, radius r: an orange rim, a hot body, a white core; k 1 → 0 as it dies.
static func dome(p: Px.Painter, F: Array, x: float, r: float, k: float) -> void:
	var e := 1.4 / r
	p.shade(x - r - 1.5, -r - 1.5, x + r + 1.5, 0.5, func(px: float, py: float):
		var d := Px.hypot(px - x, py) / r
		if d > 1.0 + e:
			return null
		return F[2] if d > 1.0 else ((F[6] if k > 0.45 else F[5]) if d > 0.8 else ((WHITE if k > 0.45 else F[6]) if d > 0.5 else (WHITE if k > 0.2 else F[6]))))


## A lobe of a billowing cloud, shaded like a ball. The sky lights it from the top left through the smoke ramp SM
## (light to dark); fire (0..1) burns in its heart in the fire ramp FR (bright to dark), shrinking toward the
## middle as it cools, with a darker band and a dark orange-red seam at its edge so a mass of burning lobes reads
## apart; glow (0..1) lights its underside from below in fire colors. a: opacity (smoke edges stay soft); z: -1 far
## .. 1 near (the far side sits a step darker); dark shifts the smoke down the ramp. style 1 cel-shades the smoke:
## a lit crescent on top, a mid tone, a dark underside the fire tints while it's hot.
static func lobe(p: Px.Painter, x: float, y: float, r: float, FR: Array, SM: Array, fire: float, glow: float, a: float, z: float = 0.0, dark: int = 0, style: int = 0) -> void:
	if r < 0.7 or a <= 0.01:
		return
	var n := FR.size()
	var m := SM.size()
	var back := 1 if z < -0.35 else 0
	var rim := 1.0 - minf(0.35, 1.6 / r)
	var seam := 1.0 - minf(0.3, 1.3 / r)
	# the soft edge: a step more see-through than the body, less of a step as the whole lobe thins (no bubble rims)
	var D := func(i: int) -> int: return SM[mini(m - 1, i + back + dark)]
	var soft := 0.55 + 0.4 * (1.0 - minf(1.0, a))
	var px := func(lx: float, ly: float, sx: int, sy: int) -> void:
		var dx := (lx - x) / r
		var dy := (ly - y) / r
		var d2 := dx * dx + dy * dy
		if d2 > 1.0:
			return
		var d := sqrt(d2)
		var nz := sqrt(1.0 - d2)
		var sky := -0.5 * dx - 0.66 * dy + 0.56 * nz
		var v := fire * (1.32 - 0.78 * d) + 0.14 * sky * fire
		var c: int
		var k := 0.0
		var solid := false
		if v > 0.44:
			var i := mini(n - 3, maxi(0, floori((1.3 - v) * (n - 1) * 0.78)))
			if d > seam:
				i = mini(6, maxi(4, i + 2))
			elif d > seam - 0.22:
				i = mini(n - 3, i + 1)
			c = FR[i]
			k = 0.05 * fire
			solid = true
		elif style:
			var lam := -0.42 * dx - 0.78 * dy + 0.46 * nz
			if lam > 0.66 and d > 0.4:
				c = D.call(0)
			elif lam > 0.16:
				c = D.call(1)
			elif lam > -0.3:
				c = D.call(2)
			else:
				c = D.call(4 if lam < -0.64 else 3)
				var g := glow * (0.6 + 0.4 * dy)
				if g > 0.55:
					c = FR[5 if g > 0.8 else 6]
					k = 0.08 * g
				elif g > 0.34:
					c = Px.mix(c, FR[6], 0.6)
				elif g > 0.16:
					c = Px.mix(c, FR[7], 0.45)
		else:
			var g := glow * (0.82 * dy + 0.3 * nz)
			if g > 0.45:
				c = FR[4 if g > 0.66 else 5]
				k = 0.1 * glow
			elif g > 0.3:
				c = FR[6]
			elif g > 0.2:
				c = FR[7]
			else:
				var s := sky * 0.5 + 0.5
				c = D.call(0 if s > 0.8 else (1 if s > 0.62 else (2 if s > 0.42 else (3 if s > 0.22 else 4))))
		p.blendPx(sx, sy, c, a if (solid or d <= rim) else a * soft)
		if k > 0.0:
			p.add(sx, sy, c, k)
	if p.sn != 0.0 or p.cs != 1.0:
		p.each(x - r, y - r, x + r, y + r, px)
		return
	# unrotated (the usual case): walk the screen pixels directly
	var ax := p.tx + (x - r) * p.fx
	var bx := p.tx + (x + r) * p.fx
	var sx0 := maxf(p.ox, floorf(minf(ax, bx)))
	var sx1 := minf(p.ox + p.w - 1, ceilf(maxf(ax, bx)))
	var sy0 := maxf(p.oy, floorf(p.ty + y - r))
	var sy1 := minf(p.oy + p.h - 1, ceilf(p.ty + y + r))
	for sy in range(int(sy0), int(sy1) + 1):
		var ly := sy + 0.5 - p.ty
		var q := (ly - y) / r
		if q * q >= 1.0:
			continue
		# only the span of this row inside the circle
		var hw := r * sqrt(1.0 - q * q)
		var cx := p.tx + x * p.fx
		for sx in range(int(maxf(sx0, floorf(cx - hw - 0.5))), int(minf(sx1, ceilf(cx + hw))) + 1):
			px.call((sx + 0.5 - p.tx) * p.fx, ly, sx, sy)


## A rolling fireball. n lobes ride a vortex ring that climbs (rise px, slowing with time constant tau, then
## drifting up at drift px/s), swells (tube and ring radii grow with time constant grow) and rolls (up through
## the middle, out over the top, down the outside, back in underneath), while it cools from white-hot fire
## into smoke that glows from inside, then thins away. Seen from a little below: the near side sits lower.
## update(dt); draw(p, FR (fire ramp, bright to dark), SM (smoke ramp, light to dark), { mid }) (mid() is drawn
## between the far and near lobes: a stem going up into it); shape() its centre and radii; hot() how hot its heart
## still is; ember() how strongly its inside still glows. Options for a nuclear cap: style 1 (cel-shaded lobes),
## inner (a glow that lingers inside and draws back to the middle as it cools), hollow (the underside sits a step
## darker), fray [t0, rate, t1] with onFray(x, y, r, ux, uy) (the rim sheds small puffs late on).
class Plume extends RefCounted:
	var o: Dictionary
	var R: Px.Rng
	var t := 0.0
	var roll := 0.0
	var onFray: Variant = null
	var lobes: Array

	func _init(R_: Px.Rng, o_: Dictionary = {}) -> void:
		o = Px.merge({
			"x": 0.0, "y": -20.0, "rise": 100.0, "tau": 1.2, "drift": 4.0, "tube": [8.0, 20.0], "ring": [1.0, 18.0], "grow": 0.9, "n": 40.0, "size": [5.0, 10.0], "swell": 0.5,
			"spin": 2.4, "spinTau": 1.6, "heat": 1.15, "cool": 0.45, "under": 0.5, "tilt": 0.2, "squash": 0.7, "fade": [4.0, 6.0], "glow": 1.0, "spread": 10.0,
			"style": 0, "inner": false, "hollow": false, "fray": null,
		}, o_)
		R = R_
		t = 0.0
		roll = 0.0
		onFray = null
		# spread over the ring evenly: the roll angle on a golden-ratio walk, the turn round the axis in order
		lobes = []
		var i := 0
		while i < o.n:
			lobes.append({
				"th": TAU * fmod(i * 0.618034 + R.range(-0.08, 0.08), 1.0), "ph": (TAU * (i + R.range(-0.35, 0.35))) / o.n,
				"j": R.range(-0.55, 0.12), "s": R.range(o.size[0], o.size[1]), "h": R.range(-0.22, 0.08), "dx": R.range(-1.0, 1.0), "dy": R.range(-1.0, 0.4),
				"f": R.range(-0.9, 0.5), "gv": R.range(0.55, 1.15),
			})
			i += 1

	func shape(t_: Variant = null) -> Dictionary:
		var tt: float = t if t_ == null else t_
		var u := maxf(0.0, tt)
		var g := 1.0 - exp(-u / o.grow)
		return {"x": o.x, "y": o.y - o.rise * (1.0 - exp(-u / o.tau)) - o.drift * u, "tube": o.tube[0] + (o.tube[1] - o.tube[0]) * g, "ring": o.ring[0] + (o.ring[1] - o.ring[0]) * g, "g": g}

	func hot(t_: Variant = null) -> float:
		var tt: float = t if t_ == null else t_
		return Px.clamp(o.heat - o.cool * tt + 0.3)

	## How strongly the inside still glows (0..1), lingering well after the fire has gone.
	func ember(t_: Variant = null) -> float:
		var tt: float = t if t_ == null else t_
		return Px.clamp((o.heat - o.cool * tt + 1.0) / 1.1)

	# where every lobe is at time t
	func lobesAt(tt: float) -> Array:
		var S := shape(tt)
		var base: float = o.heat - o.cool * tt
		var span: float = S.ring + S.tube
		if not span:
			span = 1.0
		var list := []
		for q in lobes:
			var fade := 1.0 - Px.smooth(o.fade[0] + q.f, o.fade[1] + q.f * 0.5, tt)
			var loose: float = pow(Px.smooth(o.fade[0] - 1.8 + q.f, o.fade[1], tt), 1.5) * o.spread
			if fade <= 0.0:
				continue
			var th: float = q.th - roll
			var rt: float = S.tube * (1.0 + q.j)
			var rho: float = S.ring + rt * cos(th)
			var up := sin(th)
			var X: float = rho * cos(q.ph)
			var Z: float = rho * sin(q.ph)
			# the outside cools first; the underside keeps its heat, fed from below
			var heat: float = base + q.h - 0.18 * maxf(0.0, cos(th)) * Px.clamp(tt * 2.0) + o.under * maxf(0.0, -up) * Px.clamp(base + 0.6)
			var r: float = q.s * (0.5 + 0.5 * S.g) * (1.0 + o.swell * Px.clamp(1.0 - heat)) * (1.0 + 0.35 * (1.0 - fade))
			list.append({"x": S.x + X + q.dx * loose, "y": S.y - rt * up * o.squash + Z * o.tilt + q.dy * loose, "z": Z / span, "up": up, "out": cos(th), "heat": heat, "q": q, "fade": fade, "r": r, "d": Px.hypot(X, Z) / span, "c": 1.0 - minf(1.0, absf(X) / span)})
		return Px.sort(list, func(a, b): return a.z - b.z)

	func update(dt: float) -> void:
		t += dt
		roll += o.spin * (0.12 + 0.88 * exp(-t / o.spinTau)) * dt
		# late on, the rim frays: lobes on the outside shed small puffs that drift off and thin
		if o.fray != null and onFray != null and t > o.fray[0] and t < (o.fray[2] if o.fray.size() > 2 and o.fray[2] != null else INF):
			var S := shape()
			var k: float = o.fray[1] * dt * Px.smooth(o.fray[0], o.fray[0] + 1.0, t)
			for e in lobesAt(t):
				if e.out < 0.2 or not R.chance(k * e.fade):
					continue
				var ux: float = e.x - S.x
				var uy: float = e.y - S.y
				var l := Px.hypot(ux, uy)
				if not l:
					l = 1.0
				onFray.call(e.x + (ux / l) * e.r * 0.6, e.y + (uy / l) * e.r * 0.6, e.r, ux / l, uy / l)

	func draw(p: Px.Painter, FR: Array, SM: Array, opts: Dictionary = {}) -> void:
		var mid: Variant = opts.get("mid")
		var tt := t
		if tt >= o.fade[1] + 0.5:
			return
		var S := shape(tt)
		var base: float = o.heat - o.cool * tt
		var span: float = S.ring + S.tube
		if not span:
			span = 1.0
		var list := lobesAt(tt)
		var age := Px.clamp(tt / o.fade[1])
		var E := ember(tt)
		var reach := 0.3 + 1.15 * E
		var drawn := false
		for e in list:
			if not drawn and e.z >= 0.0 and mid != null:
				drawn = true
				mid.call()
			var h: float = e.heat
			var fade: float = e.fade
			var fire := Px.clamp((h - 0.2) / 0.75)
			# the glow from inside: strongest under the middle, uneven from lobe to lobe; with inner, it draws back to the
			# middle as the cap cools
			var glow: float = (E * Px.clamp((reach - e.d) / 0.45) * (0.45 + 0.55 * maxf(0.0, -e.up)) * e.q.gv * o.glow) if o.inner else (Px.clamp((base + 0.45) / 0.85) * o.glow * (0.4 + 0.35 * maxf(0.0, -e.up) + 0.4 * e.c) * e.q.gv)
			Self.lobe(p, e.x, e.y, e.r, FR, SM, fire, glow, fade * (0.82 + 0.18 * fire), e.z, (1 if age > 0.72 else 0) + (1 if (o.hollow and e.up < -0.35) else 0), o.style)
			if fire > 0.25:
				p.glow(e.x, e.y, e.r * 1.25 + 2.0, FR[2], 0.07 * fire)
		if not drawn and mid != null:
			mid.call()
		var hot_ := hot(tt)
		if hot_ > 0.0:
			p.glow(S.x, S.y, span * 1.8 + 14.0, FR[3], 0.32 * hot_ * o.glow)
		if o.inner and E > 0.05:
			p.glow(S.x, S.y + S.tube * 0.3, span * (0.5 + 0.7 * E) + 8.0, FR[4], 0.22 * E * E)


## A rising column: lobes boil up a stem from the floor into whatever sits on top, wide at the foot, swaying,
## cooling from fire to smoke and dust. update(dt, top, feed): top is the y the stem rises to, feed 0..1 how
## strongly it's still being fed (new lobes stop when it's 0, and the stem breaks up from the bottom).
## draw(p, FR, SM, fire (0..1 heat at the foot), glow (0..1 under-light)).
class Column extends RefCounted:
	var R: Px.Rng
	var o: Dictionary
	var t := 0.0
	var lobes: Array = []
	var acc := 0.0

	func _init(R_: Px.Rng, o_: Dictionary = {}) -> void:
		R = R_
		o = Px.merge({"w": 7.0, "foot": 16.0, "speed": 70.0, "size": [5.0, 8.0], "n": 18.0, "sway": 2.5, "fade": 0.5, "style": 0}, o_)
		t = 0.0
		lobes = []
		acc = 0.0

	func spawn(y: float) -> void:
		lobes.append({"y": y, "x": R.range(-1.0, 1.0), "s": R.range(o.size[0], o.size[1]), "ph": R.range(0.0, TAU), "a": 0.0, "v": R.range(0.8, 1.2)})

	func update(dt: float, top: float, feed: float) -> void:
		var L := maxf(10.0, -top)
		t += dt
		if feed > 0.0:
			acc += dt * feed * o.n * (o.speed / L)
			while acc > 1.0:
				spawn(-1.0)
				acc -= 1.0
		var i := lobes.size() - 1
		while i >= 0:
			var b: Dictionary = lobes[i]
			var u := Px.clamp(-b.y / L)
			b.y -= o.speed * b.v * (0.45 + 0.55 * minf(1.0, -b.y / 24.0)) * dt
			b.a = minf(1.0, b.a + dt * 4.0)
			var gone: bool = b.y < top
			if not gone and feed <= 0.0:
				b.a -= dt * (2.0 - u)
				gone = b.a <= 0.0
			if gone:
				lobes.remove_at(i)
			i -= 1

	func draw(p: Px.Painter, top: float, FR: Array, SM: Array, fire: float, glow: float) -> void:
		var L := maxf(10.0, -top)
		# draw from the top down so the foot sits in front
		var list := Px.sort(lobes.duplicate(), func(a, b): return a.y - b.y)
		for b in list:
			var u := Px.clamp(-b.y / L)
			var foot := pow(1.0 - u, 4.0)
			var w: float = o.w + o.foot * foot
			var x: float = b.x * w * 0.45 + sin(t * 1.7 + b.ph + u * 3.0) * o.sway * u
			var r: float = b.s * (0.75 + 0.5 * foot + 0.35 * u) * minf(1.0, b.a * 1.5)
			var end := 1.0 - Px.smooth(0.85, 1.0, u)
			Self.lobe(p, x, b.y - r * 0.3 * foot, r, FR, SM, Px.clamp(fire * (1.1 - u * 0.9)), glow * Px.smooth(0.55, 1.0, u), minf(1.0, b.a) * end * 0.9, 0.0, 0 if u > 0.5 else 1, o.style)
