# An act: an effect performed. The character winds up, lets go and recovers, a target takes the hit, and everything
# freezes for a moment on contact. Effects describe it as data (`static var act := {...}`), so a game with its own
# character can read the same timing (actTiming). The freeze, the shake, the springy target and poses held on 12 fps
# steps are how Hollow Crown plays its skills (https://github.com/rehan-remade/hollow-crown), MIT License,
# Copyright (c) 2026 rehan-remade.
# port-of: src/core/act.js@731e56c89512650bb56dcc9318e495a2b14dd85e
extends RefCounted

const Px := preload("px.gd")
const Rig := preload("rig.gd")


static func _num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _lerp(a: float, b: float, u: float) -> float:
	return a + (b - a) * u


## Between two poses: numbers move, everything else changes at the later key.
static func lerpPose(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var out := Px.merge(Rig.STAND, a)
	var B := Px.merge(Rig.STAND, b)
	for k in B:
		var v: Variant = B[k]
		if _num(v) and _num(out.get(k)):
			out[k] = _lerp(out[k], v, u)
		elif out.get(k) == null and _num(v):
			out[k] = v
	# what the later pose doesn't mention eases back to its default
	for k in ["hx", "hy", "lean", "crouch"]:
		if B.get(k) == null and _num(out.get(k)):
			out[k] = _lerp(out[k], 0.0, u)
	if B.get("wl") == null and _num(out.get("wl")):
		out.wl = _lerp(out.wl, 1.0, u)
	return out


static func _ease(how: Variant, u: float) -> float:
	match how:
		"out":
			return 1.0 - (1.0 - u) * (1.0 - u)
		"in":
			return u * u
		"line":
			return u
	return u * u * (3.0 - 2.0 * u)


## The pose at time t on a track of keys [t, pose, how]: how a pose arrives: smoothly by default, "out" fast then
## settling, "in" slowly then fast, "snap" holding the last pose and jumping on the key. Limbs move in whole 12 fps
## steps counted from each key; the feet's position over the floor (x, y) stays smooth.
static func poseAt(track: Array, t: float) -> Dictionary:
	if t <= track[0][0]:
		return track[0][1]
	for i in track.size() - 1:
		var t0: float = track[i][0]
		var a: Dictionary = track[i][1]
		var t1: float = track[i + 1][0]
		var b: Dictionary = track[i + 1][1]
		var how: Variant = track[i + 1][2] if track[i + 1].size() > 2 else null
		if t >= t1:
			continue
		if how == "snap":
			return a
		var stepped := t0 + floorf((t - t0) * 12.0 + 1e-6) / 12.0
		var out := lerpPose(a, b, _ease(how, (stepped - t0) / (t1 - t0)))
		var u := _ease(how, (t - t0) / (t1 - t0))
		out.x = _lerp(a.get("x", 0.0) if a.get("x") != null else 0.0, b.get("x", 0.0) if b.get("x") != null else 0.0, u)
		out.y = _lerp(a.get("y", 0.0) if a.get("y") != null else 0.0, b.get("y", 0.0) if b.get("y") != null else 0.0, u)
		return out
	return track[track.size() - 1][1]


## Is the body between keys that hardly differ, or past the last?
static func isHeld(track: Array, t: float) -> bool:
	if t >= track[track.size() - 1][0] or t < track[0][0]:
		return true
	for i in track.size() - 1:
		if t >= track[i + 1][0]:
			continue
		var a := Px.merge(Rig.STAND, track[i][1])
		var b := Px.merge(Rig.STAND, track[i + 1][1])
		if not (track[i + 1][0] - track[i][0] > 0.4):
			return false
		for k in ["fx", "fy", "bx", "by", "crouch", "lean", "x", "y"]:
			if absf(float(a.get(k, 0.0) if a.get(k) != null else 0.0) - float(b.get(k, 0.0) if b.get(k) != null else 0.0)) >= 1.5:
				return false
		return true
	return true


## When an act's poses begin and end, in effect time (a loop ends when it's told to).
static func actSpan(mod: Script) -> Dictionary:
	var a: Variant = Px.Fx.actOf(mod)
	var meta := Px.Fx.metaOf(mod)
	var D: float = meta.duration
	var k: Variant = a.get("poses") if a != null else null
	var first: float = k[0][0] if (k != null and k.size()) else 0.0
	var last: float = k[k.size() - 1][0] if (k != null and k.size()) else 0.0
	return {"from": minf(0.0, first), "to": INF if meta.loop else maxf(D, last)}


static func _targets(a: Dictionary) -> Array:
	if a.get("targets") != null:
		return a.targets
	if a.get("target"):
		return [a.target]
	return []


## An act as plain data, for a game with its own character: how long the wind-up and recovery are, when to freeze and
## shake, what a target should do, and the poses themselves. Times are in the effect's own seconds: start it at 0.
static func actTiming(mod: Script) -> Variant:
	var a: Variant = Px.Fx.actOf(mod)
	if a == null:
		return null
	var span := actSpan(mod)
	var meta := Px.Fx.metaOf(mod)
	var D: float = meta.duration
	var targets := []
	for g in _targets(a):
		targets.append(g.x if g.get("x") != null else 66)
	var hits := []
	for h in a.get("hits", []):
		var push: Variant = 0 if h.get("target") == false else (h.push if h.get("push") != null else 1.2)
		hits.append({"t": h.t, "freeze": h.get("stop", 0) if h.get("stop") != null else 0, "shake": h.get("shake", 0) if h.get("shake") != null else 0, "amp": h.get("amp", 0) if h.get("amp") != null else 0, "push": push, "skin": h.get("skin"), "at": h.get("at")})
	var poses := []
	for key in a.get("poses", []):
		poses.append({"t": key[0], "how": key[2] if key.size() > 2 and key[2] != null else "smooth", "pose": key[1]})
	return {
		"windup": -span.from,
		"recovery": 0 if meta.loop else maxf(0.0, span.to - D),
		"onBody": true if a.get("onBody") else false,
		"targets": targets,
		"hits": hits,
		"poses": poses,
	}


# ---- the target: a straw dummy on a spring
const TW := 38
const TH := 52
const GHOST_LIFE := 0.16
static var TP := {}
static var DUST: Array = []
static var DUMMY := PackedInt32Array()
## What a hit can leave on the target: [color, how much of it].
static var SKINS := {}
static var STRAW: Array = []
static var REST_MASK := PackedByteArray()
static var REST_PX := PackedInt32Array()
static var NEAREST := PackedInt32Array()


static func _setup() -> void:
	if not TP.is_empty():
		return
	var tp := {"ink": "#0b0a1a", "wood": "#724c2e", "woodL": "#a0703a", "woodD": "#4e331f", "straw": "#d2aa55", "strawL": "#f0d98a", "burlapD": "#86643a", "burlap": "#b38b57", "burlapL": "#c9a26c", "red": "#9a2f3c", "redL": "#c4434f", "white": "#ffffff"}
	for k in tp:
		TP[k] = Px.hex(tp[k])
	DUST = Px.ramp(["#efe7dc", "#c9bfb8", "#8f8693", "#5a5468"])
	SKINS = {"flash": [TP.white, 1.0], "char": [Px.hex("#1a0c0e"), 0.72], "ice": [Px.hex("#a8e8ff"), 0.72], "shadow": [Px.hex("#3a1a70"), 0.5], "holy": [Px.hex("#fff4c0"), 0.5], "red": [Px.hex("#ff2040"), 0.45], "shock": [Px.hex("#8fd6ff"), 0.6], "poison": [Px.hex("#58c43a"), 0.5]}
	STRAW = [TP.strawL, TP.straw, TP.straw, TP.burlapD, TP.burlapD]
	_buildDummy()
	# the standing character, and every cell of it mapped to the nearest cell that's on the body
	REST_MASK.resize(24 * 38)
	REST_PX.resize(24 * 38)
	for r in Px.Actor.HERO2.size():
		var row: String = Px.Actor.HERO2[r]
		for c in row.length():
			if row[c] != ".":
				REST_MASK[r * 24 + c] = 1
				REST_PX[r * 24 + c] = Px.hex(Px.Actor.DUMMY_PAL[row[c]])
	NEAREST.resize(24 * 38)
	NEAREST.fill(-1)
	for r in 38:
		for c in 24:
			var best := -1
			var bd := 1000000000
			for y in range(maxi(0, r - 7), mini(38, r + 8)):
				for x in range(maxi(0, c - 7), mini(24, c + 8)):
					var d := (x - c) * (x - c) + (y - r) * (y - r)
					if REST_MASK[y * 24 + x] and d < bd:
						bd = d
						best = y * 24 + x
			NEAREST[r * 24 + c] = best


static func _dpx(x: int, y: int, c: int) -> void:
	if x >= 0 and y >= 0 and x < TW and y < TH:
		DUMMY[y * TW + x] = c


static func _dR(x: int, y: int, w: int, h: int, c: int) -> void:
	for j in h:
		for i in w:
			_dpx(x + i, y + j, c)


static func _sack(x: int, y: int, w: int, h: int) -> void:
	_dR(x + 1, y, w - 2, 1, TP.ink); _dR(x + 1, y + h - 1, w - 2, 1, TP.ink)
	_dR(x, y + 1, 1, h - 2, TP.ink); _dR(x + w - 1, y + 1, 1, h - 2, TP.ink)
	_dR(x + 1, y + 1, w - 2, h - 2, TP.burlap)
	_dR(x + w - 4, y + 1, 3, h - 2, TP.burlapD)
	_dR(x + 1, y + h - 3, w - 2, 2, TP.burlapD)
	_dR(x + 1, y + 1, 1, h - 4, TP.burlapL); _dR(x + 1, y + 1, w - 6, 1, TP.burlapL)
	# the weave
	var j := y + 2
	while j < y + h - 2:
		var i := x + 3 + (j % 2)
		while i < x + w - 4:
			_dpx(i, j, TP.burlapD)
			i += 4
		j += 3


static func _buildDummy() -> void:
	DUMMY.resize(TW * TH)
	DUMMY.fill(0)
	# the post and the crossbar
	_dR(15, 38, 8, 14, TP.ink); _dR(16, 34, 6, 18, TP.wood); _dR(16, 34, 2, 18, TP.woodL); _dR(20, 34, 2, 18, TP.woodD)
	_dR(1, 18, 36, 1, TP.ink); _dR(1, 23, 36, 1, TP.ink); _dR(1, 19, 36, 4, TP.wood); _dR(1, 19, 36, 1, TP.woodL); _dR(1, 22, 36, 1, TP.woodD)
	# straw bursting out of the ends of the arms
	for e in [[0, -1], [33, 1]]:
		var bx: int = e[0]
		var s: int = e[1]
		_dR(bx, 17, 5, 8, TP.straw)
		for d in [[2, 16, TP.straw], [3, 15, TP.strawL], [1, 17, TP.strawL], [2, 25, TP.straw], [1, 26, TP.strawL], [3, 25, TP.burlapD], [2, 19, TP.strawL], [3, 21, TP.strawL], [1, 22, TP.burlapD], [2, 23, TP.strawL]]:
			_dpx(bx + d[0], d[1], d[2])
		_dpx(bx - 1 if s < 0 else bx + 5, 19, TP.straw)
		_dpx(bx - 1 if s < 0 else bx + 5, 22, TP.strawL)
	_sack(9, 17, 20, 24)
	# the rings on its chest
	for y in range(19, 36):
		for x in range(11, 27):
			var d := Px.hypot(x - 18.5, y - 27.0)
			if (d > 4.0 and d < 5.4) or d < 1.9:
				_dpx(x, y, TP.redL if x + y < 45 else TP.red)
	# the rope belt, and straw coming out under it
	for x in range(10, 28):
		_dpx(x, 36, TP.woodL if x & 1 else TP.straw)
		_dpx(x, 37, TP.woodD if x & 1 else TP.wood)
	for d in [[11, 41, TP.straw], [12, 42, TP.strawL], [14, 41, TP.strawL], [15, 42, TP.straw], [23, 41, TP.straw], [24, 42, TP.strawL], [26, 41, TP.straw], [13, 43, TP.straw], [25, 43, TP.straw]]:
		_dpx(d[0], d[1], d[2])
	_sack(10, 1, 18, 16)
	# X for eyes and a stitched mouth
	for ex in [14, 23]:
		for d in range(-2, 3):
			_dpx(ex + d, 7 + d, TP.ink)
			_dpx(ex - d, 7 + d, TP.ink)
	for x in range(14, 24):
		_dpx(x, 12, TP.ink if x & 1 else TP.burlapD)
	for x in [15, 18, 21]:
		_dpx(x, 11, TP.ink)
		_dpx(x, 13, TP.ink)
	# the rope at its neck, and straw for hair
	for x in range(12, 26):
		_dpx(x, 16, TP.woodL if x & 1 else TP.straw)
		_dpx(x, 17, TP.wood if x & 1 else TP.woodD)
	for d in [[13, 0, TP.straw], [15, 0, TP.strawL], [18, 0, TP.straw], [21, 0, TP.strawL], [24, 0, TP.straw], [9, 4, TP.straw], [28, 6, TP.straw], [8, 7, TP.strawL], [29, 3, TP.strawL]]:
		_dpx(d[0], d[1], d[2])


## A straw target on a spring: it sways, flashes, takes a skin, shivers and sheds straw. (x, 0): the floor under it.
class Target:
	extends RefCounted
	var x: float
	var theta := 0.0
	var omega := 0.0
	var flashT := 0.0
	var skin: Variant = null
	var skinFade := 0.0
	var shiver := 0.0
	var clock := 0.0
	var R: Px.Rng
	var straw: Array = []

	func _init(px: float, seed: Variant = 5) -> void:
		x = px
		R = Px.Rng.new(seed)

	func hit(h: Dictionary) -> void:
		var push: float = h.push if h.get("push") != null else 1.2
		var n: float = h.straw if h.get("straw") != null else 8.0
		var flash: float = h.flash if h.get("flash") != null else 0.05
		var sh: float = h.shiver if h.get("shiver") != null else 0.0
		var y: float = h.y if h.get("y") != null else -26.0
		omega += push
		flashT = maxf(flashT, flash)
		if h.has("skin"):
			skin = h.skin
		if sh:
			shiver = sh
		var k := 0
		while k < n:
			var back := R.next() < 0.3
			var s := {}
			s.x = x + R.range(-3, 3)
			s.y = y + R.range(-3, 3)
			s.vx = R.range(-60, -5) if back else R.range(10, 130)
			s.vy = R.range(-120, -5)
			s.age = 0.0
			s.life = R.range(1.2, 2.2)
			s.big = R.next() < 0.5
			straw.append(s)
			k += 1

	func step(dt: float) -> void:
		clock += dt
		omega += (-60.0 * theta - 3.4 * omega) * dt
		theta = Px.clamp(theta + omega * dt, -0.4, 0.42)
		if flashT > 0.0:
			flashT -= dt
		if shiver > 0.0:
			shiver -= dt
		for s in straw:
			s.age += dt
			s.vy += 210.0 * dt
			s.x += s.vx * dt
			s.y += s.vy * dt
			if s.y >= 0.0:
				s.y = 0.0
				s.vx *= 0.2
				s.vy = 0.0
		straw = straw.filter(func(s): return s.age < s.life)

	func draw(C: PackedInt32Array, W: int, H: int, X: int, Y: int, flip: bool) -> void:
		var tn := tan(theta)
		var sv := 0
		if shiver > 0.0:
			sv = 1 if floori(clock * 30.0) & 1 else -1
		var name: Variant = "flash" if flashT > 0.0 else skin
		var sk: Variant = Px.Act.SKINS[name] if name else null
		var base := X + (-int(x) - 1 if flip else int(x))
		for r in Px.Act.TH:
			var o := int(Px.round((Px.Act.TH - 1 - r) * tn * 0.8)) + sv
			for xx in Px.Act.TW:
				var c := Px.Act.DUMMY[r * Px.Act.TW + xx]
				if not c:
					continue
				var px := base + (-(xx - 19 + o) - 1 if flip else xx - 19 + o)
				var py := Y - Px.Act.TH + r
				if px >= 0 and py >= 0 and px < W and py < H:
					C[py * W + px] = Px.mix(c, sk[0], sk[1]) if sk != null else c

	func drawStraw(C: PackedInt32Array, W: int, H: int, X: int, Y: int, flip: bool) -> void:
		for s in straw:
			var c: int = Px.Act.STRAW[mini(4, floori((s.age / s.life) * 5.0))]
			var lx := int(Px.round(s.x))
			var ly := int(Px.round(s.y)) - 1
			for i in (2 if s.big else 1):
				var px := X + (-(lx + i) - 1 if flip else lx + i)
				var py := Y + ly
				if px >= 0 and py >= 0 and px < W and py < H:
					C[py * W + px] = c


static func _lum(c: int) -> float:
	return (0.3 * (c & 255) + 0.59 * ((c >> 8) & 255) + 0.11 * ((c >> 16) & 255)) / 255.0


## An effect's color over the standing body, moved onto a pixel of the pose: its color, at this pixel's own light and shade.
static func carry(v: int, rest: int, own: int) -> int:
	var lv := _lum(v)
	if lv > 0.9 or ((v >> 24) & 255) < 255:
		return v
	var k := maxf(0.45, minf(1.5, _lum(own) / maxf(0.08, _lum(rest))))
	var r := mini(255, int(Px.round((v & 255) * k)))
	var g := mini(255, int(Px.round(((v >> 8) & 255) * k)))
	var b := mini(255, int(Px.round(((v >> 16) & 255) * k)))
	return -16777216 | (b << 16) | (g << 8) | r


## An effect performed: { fx, t, update(dt), draw(frame, { body, target }), shake, done() }. t runs from the first pose
## (before the effect's own t = 0) to the last. update() holds everything still during a freeze; draw() paints the
## effect, the character and the target together. o: the effect's options, with x, y placing the feet.
static func createAct(mod: Script, o: Dictionary = {}) -> ActInstance:
	_setup()
	return ActInstance.new(mod, o)


class ActInstance:
	extends RefCounted
	var mod: Script
	var a: Dictionary
	var meta: Dictionary
	var D: float
	var flip: bool
	var seed: float
	var fx: Px.Fx.Instance
	var track: Array
	var span: Dictionary
	var X: float
	var Y: float
	var targets: Array = []
	var hits: Array = []
	var dust: Array = []
	var R: Px.Rng
	var specks: Array = []
	var ghosts: Array = []
	var gc: int
	var t: float
	var stop_ := 0.0
	var stopped := false
	var shakeT := 0.0
	var shake0 := 0.0
	var amp := 0.0
	var nh := 0
	var nd := 0
	var loopN := 0
	var gAcc := 0.0
	var last: Variant = null
	var scratch: Variant = null
	## Called with each hit as it lands (the JS out.onHit).
	var onHit: Variant = null

	func _init(m: Script, o: Dictionary) -> void:
		mod = m
		var act: Variant = Px.Fx.actOf(m)
		a = act if act != null else {}
		meta = Px.Fx.metaOf(m)
		D = meta.duration
		flip = true if o.get("flip") else false
		var mo: Dictionary = meta.get("options", {})
		seed = o.seed if o.get("seed") != null else (mo.seed if mo.get("seed") != null else 1.0)
		fx = Px.Fx.createFx(m, o)
		track = a.poses if a.get("poses") != null else [[0, Px.merge(Px.Rig.STAND)]]
		span = Px.Act.actSpan(m)
		X = o.x if o.get("x") != null else 0.0
		Y = o.y if o.get("y") != null else 0.0
		var tl: Array = Px.Act._targets(a)
		for i in tl.size():
			targets.append(Px.Act.Target.new(tl[i].x if tl[i].get("x") != null else 66.0, seed + 4 + i))
		for h in a.get("hits", []):
			hits.append((h as Dictionary).duplicate())
		Px.sort(hits, func(p, q): return p.t - q.t)
		dust = (a.get("dust", []) as Array).duplicate()
		R = Px.Rng.new(seed + 9)
		# after-images take the effect's own color unless the act names one
		var rmp: Variant = o.palette if o.get("palette") != null else mo.get("palette")
		var g: Variant = a.get("ghost")
		if g == null and rmp != null:
			g = rmp[floori(rmp.size() * 0.7)]
		gc = Px.hex(g if g != null else "#8fb4ff")
		t = span.from
		poseNow()

	func poseNow() -> Dictionary:
		var tt := t
		if meta.loop and t >= D:
			tt = fmod(t, D)
		var q := Px.Act.poseAt(track, tt)
		# nothing is asked of him: he breathes
		if not meta.loop and Px.Act.isHeld(track, tt):
			var up := floori(tt * 3.0) & 1
			q = Px.merge(Px.merge(Px.Rig.STAND, q), {
				"crouch": float(q.get("crouch", 0.0) if q.get("crouch") != null else 0.0) + up,
				"fy": float(q.fy if q.get("fy") != null else Px.Rig.STAND.fy) + up,
				"by": float(q.by if q.get("by") != null else Px.Rig.STAND.by) + up,
			})
		last = q
		return q

	## How far the whole picture is thrown right now, in px: [x, y].
	func shake() -> Array:
		if shakeT <= 0.0:
			return [0, 0]
		var k := amp * (shakeT / shake0)
		var f := floorf(shakeT * 60.0)
		return [int(Px.round(sin(f * 2.4) * k)), int(Px.round(cos(f * 3.7) * k * 0.7))]

	func frozen() -> bool:
		return stop_ > 0.0

	## The pose he's in right now.
	func pose() -> Variant:
		return last

	func update(dt: float) -> void:
		if shakeT > 0.0:
			shakeT -= dt
		if stop_ > 0.0:
			stop_ -= dt
			return
		var t0 := t
		t += dt
		if t >= 0.0:
			fx.update(t if t0 < 0.0 else dt)
		if meta.loop and t >= D:
			var n := floori(t / D)
			if n != loopN:
				loopN = n
				nh = 0
				nd = 0
		var tt := fmod(t, D) if (meta.loop and t >= D) else t
		while nh < hits.size() and hits[nh].t <= tt:
			var h: Dictionary = hits[nh]
			if h.get("stop"):
				stop_ = maxf(stop_, h.stop)
			if h.get("shake"):
				shakeT = h.shake
				shake0 = h.shake
				amp = h.amp if h.get("amp") != null else 2.0
			if h.get("target") != false:
				for i in targets.size():
					if h.get("at") == null or int(h.at) == i:
						targets[i].hit(h)
			if onHit is Callable:
				onHit.call(h)
			nh += 1
		while nd < dust.size() and dust[nd].t <= tt:
			var d: Dictionary = dust[nd]
			var n: float = d.n if d.get("n") != null else 6.0
			var i := 0
			while i < n:
				var dir: float = d.dir if d.get("dir") != null else (-1.0 if R.next() < 0.5 else 1.0)
				var s := {}
				s.x = d.x + R.range(-3, 3)
				s.y = -1.0 - R.range(0, 2)
				s.vx = dir * R.range(22, 90)
				s.vy = R.range(-34, -6)
				s.age = 0.0
				s.life = R.range(0.16, 0.4)
				s.big = R.next() < 0.45
				s.c = Px.hex(d.c) if d.get("c") else 0
				specks.append(s)
				i += 1
			nd += 1
		for k in specks:
			k.age += dt
			k.vx *= 1.0 - 5.0 * dt
			k.vy += 110.0 * dt
			k.x += k.vx * dt
			k.y = minf(-1.0, k.y + k.vy * dt)
		var j := specks.size() - 1
		while j >= 0:
			if specks[j].age >= specks[j].life:
				specks.remove_at(j)
			j -= 1
		var q := poseNow()
		for g in targets:
			g.step(dt)
		# after-images while a key asks for them
		gAcc += dt
		if q.get("ghost") and gAcc >= 1.0 / 30.0:
			gAcc = 0.0
			ghosts.append({"q": q, "age": 0.0})
			if ghosts.size() > 7:
				ghosts.pop_front()
		for g in ghosts:
			g.age += dt
		while ghosts.size() and ghosts[0].age > Px.Act.GHOST_LIFE:
			ghosts.pop_front()

	func _scratchFor(f: Px.Frame) -> Array:
		if scratch == null or scratch[0].w != f.w or scratch[0].h != f.h:
			scratch = [Px.createFrame(f.w, f.h, f.ox, f.oy), Px.createFrame(f.w, f.h, f.ox, f.oy)]
		return scratch

	## Paint it. opts { body: false } leaves the character out, { target: false } the target.
	func draw(frame: Px.Frame, opts: Dictionary = {}) -> void:
		var body: bool = opts.get("body", true)
		var showTarget: bool = opts.get("target", true)
		var W := frame.w
		var H := frame.h
		var q: Dictionary = last if last != null else poseNow()
		var active := t >= 0.0
		var tgt: Array = targets if showTarget else []
		var FX := int(X) - frame.ox
		var FY := int(Y) - frame.oy
		var C := frame.color
		var Lb := frame.light
		if not body:
			if active:
				fx.draw(frame, "back")
			for g in tgt:
				g.draw(C, W, H, FX, FY, flip)
			if active:
				fx.draw(frame, "front")
			for g in tgt:
				g.drawStraw(C, W, H, FX, FY, flip)
			return
		var rx := int(Px.round(q.x if q.get("x") != null else 0.0))
		var ry := int(Px.round(q.y if q.get("y") != null else 0.0))
		var BX := FX + (-rx if flip else rx)
		var BY := FY + ry
		var r := Px.Rig.posed(q)
		if not a.get("onBody"):
			# the effect doesn't care about the body: back, body, front
			if active:
				fx.draw(frame, "back")
			for g in tgt:
				g.draw(C, W, H, FX, FY, flip)
			_shadow(frame, q, FX, FY, rx, ry)
			_ghosts(frame, FX, FY)
			for i in r.n:
				_paint(frame, r, i, r.color[i], BX, BY)
			if active:
				fx.draw(frame, "front")
			for g in tgt:
				g.drawStraw(C, W, H, FX, FY, flip)
			_dust(frame, FX, FY)
			return
		# the effect paints the standing body: draw it there, then carry each body pixel to where the pose put it
		var sc := _scratchFor(frame)
		var A: Px.Frame = sc[0]
		var B: Px.Frame = sc[1]
		A.clear()
		B.clear()
		if active:
			fx.draw(A, "back")
		B.color = A.color.duplicate()
		B.light = A.light.duplicate()
		var tt := (0.0 if t < 0.0 else fmod(t, D)) if meta.loop else Px.clamp(t, 0.0, D)
		var alpha := Px.Actor.actorAlphaOf(mod, tt, fx.options) if active else 1.0
		var actor: Variant = fx.options.get("actor")
		Px.drawActor(Px.painterFor(B).place(FX, FY, flip), actor if actor != null else Px.stockActor(2), alpha)
		if active:
			fx.draw(B, "front")
		var follow: float = a.follow if a.get("follow") != null else 1.0
		var lean: float = float(q.lean if q.get("lean") != null else 0.0) * follow
		var cr: float = float(q.crouch if q.get("crouch") != null else 0.0) * follow
		for g in tgt:
			g.draw(C, W, H, FX, FY, flip)
		_shadow(frame, q, FX, FY, rx, ry)
		var AC := A.color
		var BC := B.color
		var BL := B.light
		for sy in H:
			for sx in W:
				var c := AC[sy * W + sx]
				if c:
					_copy(frame, false, sx, sy, c, FY, lean, cr, rx, ry)
		_ghosts(frame, FX, FY)
		var REST_PX := Px.Act.REST_PX
		var NEAREST := Px.Act.NEAREST
		for i in r.n:
			var s: int = NEAREST[r.src[i]] if r.src[i] >= 0 else -1
			if s < 0:
				if alpha > 0.5:
					_paint(frame, r, i, r.color[i], BX, BY)
				continue
			var cc := s % 24
			var r0 := floori(s / 24.0)
			var rsx := FX - (cc - 12) - 1 if flip else FX + cc - 12
			var rsy := FY + r0 - 38
			var jj := rsy * W + rsx if (rsx >= 0 and rsy >= 0 and rsx < W and rsy < H) else -1
			var v: int = BC[jj] if jj >= 0 else REST_PX[s]
			if not v:
				continue
			_paint(frame, r, i, r.color[i] if v == REST_PX[s] else Px.Act.carry(v, REST_PX[s], r.color[i]), BX, BY)
		for sy in H:
			for sx in W:
				var j := sy * W + sx
				if BC[j] and BC[j] != AC[j] and not _rest(sx, sy, FX, FY):
					_copy(frame, false, sx, sy, BC[j], FY, lean, cr, rx, ry)
				if BL[j] & 0xffffff:
					_copy(frame, true, sx, sy, BL[j], FY, lean, cr, rx, ry)
		for g in tgt:
			g.drawStraw(C, W, H, FX, FY, flip)
		_dust(frame, FX, FY)

	func _paint(frame: Px.Frame, r: Dictionary, i: int, color: int, BX: int, BY: int) -> void:
		var px: int = BX - r.xs[i] - 1 if flip else BX + r.xs[i]
		var py: int = BY + r.ys[i]
		if px < 0 or py < 0 or px >= frame.w or py >= frame.h:
			return
		frame.color[py * frame.w + px] = color
		# he stays crisp in front of his own after-images
		if ghosts.size():
			frame.light[py * frame.w + px] = 0

	func _ghosts(frame: Px.Frame, FX: int, FY: int) -> void:
		var W := frame.w
		var H := frame.h
		var L := frame.light
		for g in ghosts:
			# after-images are light, not paint: they brighten what's behind them and leave nothing muddy
			var gq: Dictionary = g.q
			var gr := Px.Rig.posed(gq)
			var qx := int(Px.round(gq.x if gq.get("x") != null else 0.0))
			var gx := FX + (-qx if flip else qx)
			var gy := FY + int(Px.round(gq.y if gq.get("y") != null else 0.0))
			var k: float = 0.5 * (1.0 - g.age / Px.Act.GHOST_LIFE)
			var r0 := (gc & 255) * k
			var g0 := ((gc >> 8) & 255) * k
			var b0 := ((gc >> 16) & 255) * k
			for i in gr.n:
				var px: int = gx - gr.xs[i] - 1 if flip else gx + gr.xs[i]
				var py: int = gy + gr.ys[i]
				if px < 0 or py < 0 or px >= W or py >= H:
					continue
				var j := py * W + px
				var d := L[j]
				L[j] = -16777216 | (int(minf(255.0, ((d >> 16) & 255) + b0)) << 16) | (int(minf(255.0, ((d >> 8) & 255) + g0)) << 8) | int(minf(255.0, (d & 255) + r0))

	func _shadow(frame: Px.Frame, q: Dictionary, FX: int, FY: int, rx: int, ry: int) -> void:
		var W := frame.w
		var H := frame.h
		var sy := FY
		var cx := FX + (-rx if flip else rx)
		# a pose without its feet given: JS's Math.abs(undefined - undefined) >> 1 is 0
		var feet: int = 0 if (q.get("ffx") == null or q.get("fbx") == null) else (int(absf(q.ffx - q.fbx)) >> 1)
		var hw := 10 + feet - mini(8, absi(ry) >> 1)
		if sy < 0 or sy >= H:
			return
		var C := frame.color
		for dy in 2:
			for x in range(-hw + dy * 2, hw - dy * 2 + 1):
				var px := cx + x
				var i := (sy + dy) * W + px
				if px < 0 or px >= W or sy + dy >= H:
					continue
				var c := C[i]
				C[i] = (c & 0xffffff) | (maxi((c >> 24) & 255, 110) << 24)

	func _dust(frame: Px.Frame, FX: int, FY: int) -> void:
		var W := frame.w
		var H := frame.h
		for k in specks:
			var c: int = k.c if k.c else Px.Act.DUST[mini(3, floori((k.age / k.life) * 4.0))]
			var lx := int(Px.round(k.x))
			var py := FY + int(Px.round(k.y))
			for i in (2 if k.big else 1):
				var px := FX - lx - i - 1 if flip else FX + lx + i
				if px >= 0 and py >= 0 and px < W and py < H:
					frame.color[py * W + px] = c

	func _rest(sx: int, sy: int, FX: int, FY: int) -> bool:
		var c := (FX - sx - 1 if flip else sx - FX) + 12
		var r0 := sy - FY + 38
		return c >= 0 and r0 >= 0 and c < 24 and r0 < 38 and Px.Act.REST_MASK[r0 * 24 + c] == 1

	# what's up on the body goes with it; what's on the floor stays on the floor
	func _copy(frame: Px.Frame, light: bool, sx: int, sy: int, s: int, FY: int, lean: float, cr: float, rx: int, ry: int) -> void:
		var ly := sy - FY
		var k := Px.clamp((-11.0 - ly) / 7.0, 0.0, 1.0)
		var f := Px.clamp((-1.0 - ly) / 6.0, 0.0, 1.0)
		var dx := int(Px.round(lean * k + rx * f))
		var dy := int(Px.round(cr * k + ry * f))
		var px := sx + (-dx if flip else dx)
		var py := sy + dy
		var W := frame.w
		if px < 0 or py < 0 or px >= W or py >= frame.h:
			return
		var i := py * W + px
		if light:
			var d := frame.light[i]
			frame.light[i] = -16777216 | (mini(255, ((d >> 16) & 255) + ((s >> 16) & 255)) << 16) | (mini(255, ((d >> 8) & 255) + ((s >> 8) & 255)) << 8) | mini(255, (d & 255) + (s & 255))
			return
		var C := frame.color
		var sa := (s >> 24) & 255
		if sa == 255 or not C[i]:
			C[i] = s
		else:
			var kk := sa / 255.0
			var d := C[i]
			var r := int(Px.round((s & 255) * kk + (d & 255) * (1.0 - kk)))
			var g := int(Px.round(((s >> 8) & 255) * kk + ((d >> 8) & 255) * (1.0 - kk)))
			var b := int(Px.round(((s >> 16) & 255) * kk + ((d >> 16) & 255) * (1.0 - kk)))
			C[i] = (maxi(sa, (d >> 24) & 255) << 24) | (b << 16) | (g << 8) | r

	## Let a loop end: it fades out and done() goes true.
	func stop() -> void:
		fx.stop()
		stopped = true

	## One-shots end when the last pose is over.
	func done() -> bool:
		return fx.done() if stopped else (t >= span.to and stop_ <= 0.0)


## The box an act needs in local space, so nothing gets cut off: { x0, y0, x1, y1 }, sampled over its poses.
static func actBounds(mod: Script) -> Dictionary:
	_setup()
	var a: Variant = Px.Fx.actOf(mod)
	var meta := Px.Fx.metaOf(mod)
	var w: int = meta.size[0]
	var h: int = meta.size[1]
	var ox: int = meta.origin[0]
	var oy: int = meta.origin[1]
	var b := {"x0": -ox, "y0": -oy, "x1": w - ox, "y1": h - oy}
	var k: Variant = a.get("poses") if a != null else null
	if k != null:
		var t: float = k[0][0]
		var end: float = k[k.size() - 1][0]
		while t <= end:
			_see(b, poseAt(k, t))
			t += 1.0 / 12.0
		for key in k:
			_see(b, key[1])
	else:
		_see(b, Rig.STAND)
	if a != null:
		for g in _targets(a):
			var tx: float = g.x if g.get("x") != null else 66.0
			b.x0 = minf(b.x0, tx - 30.0)
			b.x1 = maxf(b.x1, tx + 36.0)
			b.y0 = minf(b.y0, -56.0)
	return b


static func _see(b: Dictionary, p: Dictionary) -> void:
	var r := Rig.posed(p)
	var X := Px.round(p.x if p.get("x") != null else 0.0)
	var Y := Px.round(p.y if p.get("y") != null else 0.0)
	b.x0 = minf(b.x0, r.x0 + X - 1)
	b.x1 = maxf(b.x1, r.x1 + X + 1)
	b.y0 = minf(b.y0, r.y0 + Y - 1)
	b.y1 = maxf(b.y1, r.y1 + Y + 1)
