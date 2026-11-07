# A particle system (JS `new Particles(opts)` from src/core/sim.js). opts: { rng | seed, ground: Callable(x) -> floor y
# (local px; sparks bounce on it), sparks: [head..tail] colors for SPARK, haze: color vapour glows with, onLand:
# Callable(x, y) when a BRAND hits the floor }. spawn(kind, x, y, vx, vy, life, color, size, delay, flag); update(dt);
# draw(p, layer): "back" draws the soft kinds (vapour, dust, smoke) and PF.BACK ones, "front" the rest, "" both.
# Particles are Dictionaries ({ k, x, y, vx, vy, life, max, col, size, seed, delay, flag }), so effects may add fields.
# Adapted from Sprite Fusion's open-source pixel art VFX (https://www.spritefusion.com/pixel-art-vfx),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/core/sim.js@68f1a7097a6cf263b03d61a5144cfdb3938e4850 (class Particles)
extends RefCounted

const Px := preload("px.gd")
const Sim := preload("sim.gd")
const Rng := preload("rng.gd")
const P := Sim.P
const PF := Sim.PF
const GRAVITY := Sim.GRAVITY
const WHITE := -1

var R: Rng
var list: Array = []
var t := 0.0
var ground: Variant = null
var _gn := 0
var sparks: Array
var haze: Variant = null
var onLand: Variant = null
var count: int:
	get: return list.size()


func _init(opts: Dictionary = {}) -> void:
	R = opts.rng if opts.get("rng") != null else Rng.new(opts.get("seed", 1))
	ground = opts.get("ground")
	_gn = ground.get_argument_count() if ground is Callable else 0
	sparks = Px.ramp(opts.sparks if opts.get("sparks") != null else Sim.HOT)
	haze = null if opts.get("haze") == null else Px.hex(opts.haze)
	onLand = opts.get("onLand")


func _floor(x: float) -> float:
	if ground == null:
		return INF
	return ground.call(x) if _gn >= 1 else ground.call()


static func _soft(k: int) -> bool:
	return k == P.VAPOUR or k == P.DUST or k == P.SMOKE


## delay: seconds before it appears; flag: PF bits. col 0 lets FIRE and SMOKE use their own ramps.
func spawn(k: int, x: float, y: float, vx: float, vy: float, life: float, col: Variant = WHITE, size: float = 1.0, delay: float = 0.0, flag: int = 0) -> void:
	list.append({"k": k, "x": x, "y": y, "vx": vx, "vy": vy, "life": life, "max": life, "col": Px.hex(col) if col else 0, "size": size, "seed": R.next() * 100.0, "delay": delay, "flag": flag})


func update(dt: float) -> void:
	t += dt
	var i := list.size() - 1
	while i >= 0:
		var idx := i
		i -= 1
		var p: Dictionary = list[idx]
		if p.delay > 0.0:
			p.delay -= dt
			continue
		p.life -= dt
		if p.life <= 0.0:
			if p.k == P.FIRE and p.flag & PF.SMOKES:
				var big: int = p.flag & PF.BIG
				spawn(P.SMOKE, p.x, p.y, p.vx * 0.6, p.vy * 0.6 - 6.0, R.range(1.3, 2.3) if big else R.range(0.8, 1.4), 0, p.size * (0.85 if big else 0.7), 0.0, PF.BIG if big else 0)
			list.remove_at(idx)
			continue
		match p.k:
			P.FIRE:
				p.vy -= 95.0 * dt
				p.vx += sin(t * 17.0 + p.seed) * 30.0 * dt
				p.vx -= p.vx * 5.0 * dt
				p.vy -= p.vy * 3.2 * dt
			P.GRIT:
				p.vy += GRAVITY * dt
				p.vx -= p.vx * 0.8 * dt
				var g := _floor(p.x)
				var ny: float = p.y + p.vy * dt
				p.x += p.vx * dt
				if p.vy > 0.0 and p.y <= g and ny >= g:
					p.y = g - 0.25
					if p.vy > 130.0 and R.chance(0.4):
						p.vy = -p.vy * 0.25
						p.vx = p.vx * 0.5 + R.range(-10.0, 10.0)
					else:
						p.vx = 0.0
						p.vy = 0.0
						p.life = minf(p.life, 0.5)
				else:
					p.y = ny
				continue
			P.BRAND:
				# a burning chunk: arcs, trails flame, and starts a little fire where it lands
				p.vy += GRAVITY * 0.8 * dt
				p.vx -= p.vx * 0.9 * dt
				if R.chance(0.9 * minf(1.0, dt * 60.0)):
					spawn(P.FIRE, p.x, p.y, p.vx * 0.1 + R.range(-7.0, 7.0), p.vy * 0.1 - 10.0, R.range(0.16, 0.32), 0, R.range(0.9, 1.7) * (0.5 + (p.life / p.max) * 0.6), 0.0, PF.SMOKES if R.chance(0.4) else 0)
				var g := _floor(p.x)
				var ny: float = p.y + p.vy * dt
				p.x += p.vx * dt
				if p.vy > 0.0 and p.y <= g and ny >= g:
					if onLand is Callable:
						onLand.call(p.x, g)
					list.remove_at(idx)
				else:
					p.y = ny
				continue
			P.SPARK:
				p.vy += GRAVITY * 0.45 * dt
				p.vx -= p.vx * 2.2 * dt
				p.vy -= p.vy * 2.2 * dt
				var g := _floor(p.x)
				var ny: float = p.y + p.vy * dt
				p.x += p.vx * dt
				if p.vy > 0.0 and p.y <= g and ny >= g:
					p.vy = -p.vy * 0.45
					p.vx *= 0.7
					p.y = g - 0.25
				else:
					p.y = ny
				continue
			P.STREAK:
				p.vx += p.vx * 3.0 * dt
				p.vy += p.vy * 3.0 * dt
			P.FLAKE:
				p.vx -= p.vx * 2.2 * dt
				p.vy -= p.vy * 2.2 * dt - 35.0 * dt
				p.x += sin(t * 2.5 + p.seed) * 7.0 * dt
			P.EMBER:
				p.vy += (-30.0 + sin(t * 3.0 + p.seed) * 20.0) * dt
				p.vx += cos(t * 2.3 + p.seed) * 45.0 * dt
				p.vx -= p.vx * 1.6 * dt
				p.vy -= p.vy * 1.6 * dt
			P.SMOKE:
				var big: int = p.flag & PF.BIG
				p.vy -= (23.0 if big else 16.0) * dt
				p.vx += sin(t * 1.3 + p.seed) * 8.0 * dt
				p.vx -= p.vx * 1.6 * dt
				p.vy -= p.vy * 1.2 * dt
			P.MOTE:
				p.vx -= p.vx * 0.6 * dt
				p.vy -= p.vy * 0.6 * dt
			_:
				var drag := 4.0 if _soft(p.k) else 1.6
				p.vx -= p.vx * drag * dt
				p.vy -= p.vy * drag * dt + 5.0 * dt
		p.x += p.vx * dt
		p.y += p.vy * dt


func draw(p: Variant, layer: Variant = null) -> void:
	for q: Dictionary in list:
		if q.delay > 0.0:
			continue
		if layer and ("back" if (_soft(q.k) or q.flag & PF.BACK) else "front") != layer:
			continue
		var k: float = q.life / q.max
		var x: float = q.x
		var y: float = q.y
		var sp := Px.hypot(q.vx, q.vy)
		if not sp:
			sp = 1.0
		var ux: float = q.vx / sp
		var uy: float = q.vy / sp
		match q.k:
			P.SPARK:
				var S := sparks
				var head: int = S[0] if k > 0.6 else (S[1] if k > 0.3 else S[2])
				var ln := minf(9.0, 1.0 + sp * 0.022)
				p.line(x - ux * ln, y - uy * ln, x - ux * ln * 0.4, y - uy * ln * 0.4, head if k > 0.5 else S[S.size() - 1])
				p.line(x - ux * ln * 0.45, y - uy * ln * 0.45, x, y, head)
				p.glow(x, y, 3.0, head, 0.45 * k)
			P.MOTE:
				var ln: float = minf(16.0, 0.5 + sp * 0.026) * q.size
				var a := k / 0.35 if k < 0.35 else 1.0
				p.line(x - ux * ln, y - uy * ln, x - ux * ln * 0.35, y - uy * ln * 0.35, Px.scale(q.col, 0.55), a)
				p.line(x - ux * ln * 0.4, y - uy * ln * 0.4, x, y, q.col, a)
				p.glow(x, y, 2.5 + q.size, q.col, 0.4 * k)
			P.STREAK:
				var Ls := Px.clamp(sp / 30.0, 1.0, 7.0)
				var d := Ls
				while d >= 0.0:
					p.dot(x - ux * d, y - uy * d, WHITE if d < 1.0 else (q.col if d < Ls * 0.5 else Px.scale(q.col, 0.6)), 1.0 if d < Ls * 0.5 else 1.2 - d / Ls)
					d -= 0.5
				p.glow(x, y, 4.0, q.col, 0.4)
			P.FLAKE:
				var a := minf(1.0, k * 3.0)
				p.dot(x, y, q.col, a)
				if q.size > 1.3:
					for o in Px.CROSS:
						p.dot(x + o[0], y + o[1], Px.scale(q.col, 0.8), a * 0.8)
			P.VAPOUR:
				var r: float = q.size * (0.6 + (1.0 - k) * 0.9)
				p.disc(x, y, r, q.col, pow(k, 1.3) * 0.45)
				if haze:
					p.glow(x, y, r * 1.8, haze, 0.16 * k)
			P.DUST:
				p.disc(x, y, q.size * (0.6 + (1.0 - k) * 0.9), q.col, pow(k, 1.3) * 0.7)
			P.SMOKE:
				# three soft discs: a body, a denser core sitting low, a lit cap while it's young
				var age := 1.0 - k
				var big: int = q.flag & PF.BIG
				var r: float = q.size * (0.65 + minf(1.0, age * 2.5) * 0.45 + age * (0.5 if big else 0.4))
				var a := minf(1.0, age * 12.0) * minf(1.0, k * 2.4) * (0.7 if big else 0.58)
				var c: int = Px.mix(q.col, Sim.rampAt(Sim.SMOKE_RAMP, age), age) if q.col else Sim.rampAt(Sim.SMOKE_RAMP, age * 1.05)
				p.disc(x, y, r, c, a * 0.45)
				p.disc(x + r * 0.05, y + r * 0.06, r * 0.74, c, a * 0.62)
				if age < 0.5:
					p.disc(x - r * 0.22, y - r * 0.3, r * 0.5, Px.mix(c, WHITE, 0.12), a * 0.4 * (1.0 - age * 2.0))
			P.FIRE:
				# a ball of flame that cools down the ramp as it rises: a darker rim, a lit core, a tongue on top
				var age := 1.0 - k
				var heat := minf(0.999, pow(age, 0.62) + fmod(q.seed, 1.0) * 0.1)
				var F: Array = Sim.FIRE_RAMP
				var n := F.size()
				var idx := mini(n - 2, floori(heat * (n - 1)))
				var r: float = q.size * (0.55 + 0.45 * minf(1.0, age * 7.0)) * (1.0 - age * 0.55)
				var c: int = F[idx]
				if idx >= n - 2:
					p.disc(x, y, r, c, minf(1.0, k * 3.0) * 0.85)
				else:
					p.circle(x, y, r, F[mini(n - 1, idx + 2)])
					p.circle(x - r * 0.16, y - r * 0.22, r * 0.78, c)
					if r > 1.6:
						p.circle(x, y - r * 0.9, r * 0.42, c)
					if idx <= 3 and r > 1.8:
						p.circle(x - r * 0.28, y - r * 0.34, r * 0.36, F[maxi(0, idx - 1)])
					if idx < 6:
						p.glow(x, y, r * 2.4 + 2.0, c, 0.18 * k)
			P.BRAND:
				p.circle(x, y, 1.6, Sim.HOT[3])
				p.px(x, y, Sim.HOT[0] if sin(t * 40.0 + q.seed) > 0.0 else Sim.HOT[1])
				p.px(x + 1.0, y, Sim.HOT[1])
				p.glow(x, y, 7.0, Sim.HOT[2], 0.45)
			P.GRIT:
				if k > 0.25 or k * 4.0 > 0.5:
					p.px(x, y, q.col)
					if q.size >= 2.0:
						p.px(x + 1.0, y, q.col)
						p.px(x, y + 1.0, Px.scale(q.col, 0.8))
						p.px(x + 1.0, y + 1.0, Px.scale(q.col, 0.7))
			P.EMBER:
				var c: int = sparks[0] if k > 0.6 else (sparks[1] if k > 0.3 else sparks[2])
				if k < 0.25 and sin(t * 40.0 + q.seed) < 0.0:
					continue
				p.px(x, y, c)
				if q.size > 1.5:
					p.px(x, y + 1.0, sparks[sparks.size() - 1])
				p.glow(x, y, 3.0 + q.size, c, 0.35 * k)
			_:
				# STAR: a twinkling cross, arms set by size
				var tw := 0.6 + 0.4 * sin(t * (8.0 + fmod(q.seed, 5.0)) + q.seed)
				if q.size < 1.0:
					if tw * k > 0.25:
						p.px(x, y, WHITE if tw > 0.8 else q.col)
					p.glow(x, y, 3.0, q.col, 0.4 * k * tw)
					continue
				Px.sparkle(p, x, y, q.size * tw * minf(1.0, k * 3.0), q.col, Px.scale(q.col, 0.75), 0.5 * k * tw)
