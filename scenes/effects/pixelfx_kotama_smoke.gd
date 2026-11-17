# The soft, top-lit smoke puffs (a body, a denser core, a lit cap) follow Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/spawn/poof.js@21beaeee7a5b83d79bae533862b967f901312956
extends "res://addons/pixelfx/core/effect.gd"

const Px := preload("res://addons/pixelfx/core/px.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Kotama smoke",
	"desc": "A bodyless cartoon poof: a white pop, a burst of soft lavender-white smoke balls, little stars and speed lines, lifting and thinning away.",
	"tags": ["spawn", "death", "despawn", "smoke", "poof", "cartoon", "one-shot"],
	"size": [112, 92],
	"origin": [56, 80],
	"duration": 0.9,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#2a2440", "#5e5878", "#9a94b4", "#cdc8e0", "#f2f0fa", "#ffffff"],
		"stars": ["#ffd84a", "#fff3a6", "#ffffff"],
		"seed": 21,
	},
}

const CY := -17.0

var C: Array
var S: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var balls: Array = []
var lines: Array = []
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 6)
	S = Px.fit(o.stars, 3)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [WHITE, S[1], S[0], C[2]]})
	lights = Px.Lights.new()
	# a ring of fat balls round a fat core, thrown out fast and stopped by drag, each swelling as it slows
	var ring := 9
	for i in ring:
		var a := (i / float(ring)) * TAU + R.range(-0.2, 0.2)
		var sp := R.range(95.0, 140.0)
		var r := R.range(5.0, 7.0)
		balls.append({"x": cos(a) * 3.0, "y": CY + sin(a) * 3.0, "vx": cos(a) * sp, "vy": sin(a) * sp * 0.8 - 12.0, "r0": r * 0.5, "r1": r, "life": R.range(0.7, 1.05), "delay": R.range(0.0, 0.03)})
	for i in 5:
		var a := R.range(0.0, TAU)
		var sp := R.range(20.0, 60.0)
		balls.append({"x": cos(a) * 2.0, "y": CY + sin(a) * 2.0, "vx": cos(a) * sp, "vy": sin(a) * sp - 16.0, "r0": 4.0, "r1": R.range(6.5, 8.5), "life": R.range(0.85, 1.2), "delay": R.range(0.02, 0.06)})
	# a few small puffs flung further out, gone quickly, so the cloud's edge is ragged
	for i in 7:
		var a := R.range(0.0, TAU)
		var sp := R.range(170.0, 240.0)
		var r := R.range(2.2, 3.6)
		balls.append({"x": cos(a) * 4.0, "y": CY + sin(a) * 4.0, "vx": cos(a) * sp, "vy": sin(a) * sp * 0.75 - 10.0, "r0": r * 0.6, "r1": r, "life": R.range(0.32, 0.5), "delay": R.range(0.01, 0.04)})
	for b in balls:
		b.max = b.life
	# speed lines between the balls, flicked out and gone in a few frames
	for i in 12:
		var a := (i / 12.0) * TAU + R.range(-0.12, 0.12) + 0.13
		var sa := sin(a)
		# the ones that point down stop at the floor
		lines.append({"a": a, "r1": minf(R.range(24.0, 34.0), (-2.0 - CY) / sa if sa > 0.1 else 99.0), "d": R.range(0.0, 0.04)})
	# little stars spun off the pop
	for i in 7:
		var a := R.range(-PI, 0.3)
		var sp := R.range(70.0, 125.0)
		ps.spawn(P.STAR, cos(a) * 6.0, CY + sin(a) * 6.0, cos(a) * sp, sin(a) * sp - 30.0, R.range(0.55, 0.95), R.pick([S[2], S[1], S[1], S[0]]), R.range(1.3, 2.4), R.range(0.02, 0.1))
	for i in 10:
		var a := R.range(0.0, TAU)
		var sp := R.range(40.0, 110.0)
		ps.spawn(P.STAR, cos(a) * 5.0, CY + sin(a) * 5.0, cos(a) * sp, sin(a) * sp - 20.0, R.range(0.3, 0.6), R.pick([WHITE, S[1]]), 0.6, R.range(0.0, 0.08))
	# the feet go too: a skid of dust along the floor
	for i in 6:
		var s := R.sign()
		ps.spawn(P.DUST, s * R.range(1.0, 6.0), -1.0, s * R.range(25.0, 70.0), -R.range(2.0, 10.0), R.range(0.4, 0.7), C[2], R.range(1.6, 3.0), R.range(0.02, 0.08))
	lights.add(0.0, CY, 46.0, C[4], 0.8, 0.4)
	lights.add(0.0, CY, 22.0, WHITE, 0.8, 0.1)


# a ball swells out, breathes, then shrinks to nothing (a cartoon puff goes out ball by ball, it doesn't fade)
func radius(b: Dictionary) -> float:
	var age: float = b.max - b.life
	var u: float = age / b.max
	var grow: float = b.r0 + (b.r1 - b.r0) * Px.Ease.outBack(Px.clamp(age / 0.22), 2.0)
	var breathe: float = 1.0 + 0.06 * sin(age * 14.0 + b.r1)
	return grow * breathe * (1.0 if u < 0.62 else 1.0 - Px.Ease.inBack(Px.clamp((u - 0.62) / 0.38), 1.4))


func drawBall(p: Px.Painter, b: Dictionary, layer: String) -> void:
	var age: float = b.max - b.life
	var r := radius(b)
	var a := minf(1.0, age * 20.0)
	var lit := age < 0.12
	if r < 0.6:
		return
	# the whole cloud is lit from above: the balls underneath are a step darker
	var hy: float = (b.y - CY + 6.0) / 14.0
	var lo := hy > 0.4
	var hi := hy < -0.3
	if layer == "shade":
		p.disc(b.x + r * 0.16, b.y + r * 0.2, r, C[3] if lit else (C[1] if lo else C[2]), 0.8 * a)
	elif layer == "body":
		p.disc(b.x - r * 0.06, b.y - r * 0.08, r * 0.86, C[4] if lit else (C[2] if lo else C[3]), 0.88 * a)
	elif not lo or lit:
		p.disc(b.x - r * 0.28, b.y - r * 0.34, r * 0.42, WHITE if (lit or hi) else C[4], 0.85 * a)
		if age < 0.25:
			p.disc(b.x - r * 0.3, b.y - r * 0.38, r * 0.2, WHITE, 0.9 * a * (1.0 - age / 0.25))


func update(dt: float) -> void:
	t += dt
	var i := balls.size() - 1
	while i >= 0:
		var b: Dictionary = balls[i]
		if b.delay > 0.0:
			b.delay -= dt
			i -= 1
			continue
		b.life -= dt
		if b.life <= 0.0:
			# each ball goes with a pip of light
			if b.r1 > 4.0:
				ps.spawn(P.STAR, b.x, b.y, 0.0, -8.0, 0.22, WHITE, 0.6)
			balls.remove_at(i)
			i -= 1
			continue
		# fast burst, hard drag, then a slow lift
		b.vx -= b.vx * 7.0 * dt
		b.vy -= b.vy * 7.0 * dt + 30.0 * dt
		b.x += b.vx * dt
		b.y = minf(b.y + b.vy * dt, -radius(b) * 0.7)
		i -= 1
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# a soft shadow where the body stood, and the light of the pop on the floor
	var s := 1.0 - Px.smooth(0.1, 0.9, t)
	if s > 0.0:
		p.glow(0.0, -1.0, 26.0, C[4], 0.25 * s)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	# the cloud: shade, body, then caps, so neighbouring balls merge into one lumpy cloud
	var live := balls.filter(func(b): return b.delay <= 0.0)
	for layer in ["shade", "body", "cap"]:
		for b in live:
			drawBall(p, b, layer)
	# the pop: a white ball and an 8-ray flare for a couple of frames, then a ring
	if t < 0.07:
		var k := t / 0.07
		p.circle(0.0, CY, 9.0 + 3.0 * k, C[4])
		p.circle(0.0, CY, 7.0 + 3.0 * k, WHITE)
		Px.flare(p, 0.0, CY, 20.0 * (1.0 - k * 0.5), 1.0 - k, C)
	var rk := (t - 0.03) / 0.2
	if rk > 0.0 and rk < 1.0:
		p.ring(0.0, CY, 8.0 + 18.0 * Px.Ease.outCubic(rk), maxf(1.0, 2.5 * (1.0 - rk)), WHITE if rk < 0.3 else C[4], 1.1 - rk)
	for l in lines:
		var u: float = (t - l.d) / 0.2
		if u <= 0.0 or u >= 1.0:
			continue
		var head: float = 8.0 + (l.r1 - 8.0) * Px.Ease.outExpo(Px.clamp(u / 0.6))
		var tail: float = 8.0 + (l.r1 - 8.0) * Px.Ease.inCubic(u)
		var ca := cos(l.a)
		var sa := sin(l.a)
		p.line(ca * tail, CY + sa * tail, ca * head, CY + sa * head, func(v): return WHITE if v > 0.6 else C[4])
		p.glowLine(ca * tail, CY + sa * tail, ca * head, CY + sa * head, 3.0, C[4], 0.25)
	ps.draw(p, "front")
	lights.draw(p)
