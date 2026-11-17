# The blink (gathering light, a white flash, a vertical line collapsing, a flare and sparks) is adapted from
# Sprite Fusion's open-source blink (https://www.spritefusion.com/pixel-art-vfx/movement),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/blink-out.js@d905aa3977e9461ec92b829d19a005dbdae43b71
# ENN adaptation: bodyless (no actor repaint), no floor ring, fixed player-center origin.
extends "res://addons/pixelfx/core/effect.gd"

const Px := preload("res://addons/pixelfx/core/px.gd")
const P := Px.P
const WHITE := Px.WHITE
const KOTAMA_BLINK_PALETTE := [
	"#0b0d24",
	"#181a4a",
	"#28317e",
	"#3553b4",
	"#4f86e6",
	"#8bc4ff",
	"#d2efff",
	"#ffffff",
]

const OUT := 0.32
const SQUEEZE := 0.12
const COLLAPSE := 0.08
const POP := OUT + SQUEEZE + COLLAPSE
const TIME_SCALE := 1.6 / 0.5
const FX_CENTER_Y := -22.0
const FX_HALF_H := 24.0

static var meta := {
	"name": "Kotama blink out",
	"desc": "Bodyless vanish: gathering streaks, a white flash, a vertical line collapsing to a point, then a flare and sparks; no actor body, no floor ring.",
	"tags": ["arcane", "blink", "teleport", "vanish", "movement", "magic", "one-shot"],
	"size": [136, 96],
	"origin": [68, 80],
	"duration": 0.5,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"options": {"palette": KOTAMA_BLINK_PALETTE, "seed": 11},
}

var C: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var mx := 0.0
var my := FX_CENTER_Y
var COLS: Array
var t := 0.0
var out := false
var popped := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[4]]})
	lights = Px.Lights.new()
	COLS = [WHITE, C[6], C[6], C[5], C[4]]


func update(dt: float) -> void:
	var sdt := dt * TIME_SCALE
	t += sdt
	if t < OUT - 0.04 and R.chance(0.7):
		var a := R.range(0.0, TAU)
		var d := R.range(22.0, 44.0)
		var tt := R.range(0.12, 0.18)
		var v := (d * 3.0) / (exp(3.0 * tt) - 1.0)
		var x := mx + cos(a) * d
		var y := minf(-2.0, my + sin(a) * d)
		var l := Px.hypot(x - mx, y - my)
		if not l:
			l = 1.0
		ps.spawn(P.STREAK, x, y, ((mx - x) / l) * v, ((my - y) / l) * v, tt, C[6] if R.chance(0.5) else C[5])
	if not out and t >= OUT:
		out = true
		lights.add(mx, my - 6.0, 54.0, C[5], 0.9, 0.3)
		lights.add(mx, my, 26.0, WHITE, 0.8, 0.1)
	if not popped and t >= POP:
		popped = true
		lights.add(mx, my - 6.0, 58.0, C[5], 0.9, 0.35)
		lights.add(mx, my, 24.0, WHITE, 0.9, 0.08)
		# bodyless pop: embers from a short vertical band instead of the actor silhouette
		for i in 90:
			var y: float = my + R.range(-FX_HALF_H, FX_HALF_H)
			var s := R.sign()
			ps.spawn(P.EMBER, mx + R.range(-1.0, 1.0), y, s * R.range(25.0, 105.0), R.range(-70.0, 10.0), R.range(0.5, 0.95), R.pick(COLS), 2.0 if R.chance(0.3) else 1.0)
		for i in 18:
			var a := R.range(0.0, TAU)
			var sp := R.range(80.0, 240.0)
			ps.spawn(P.SPARK, mx, my, cos(a) * sp, sin(a) * sp - 40.0, R.range(0.2, 0.5))
		for i in 14:
			var a := R.range(0.0, TAU)
			var sp := R.range(20.0, 110.0)
			ps.spawn(P.STAR if i % 2 else P.MOTE, mx, my, cos(a) * sp, sin(a) * sp * 0.8 - 20.0, R.range(0.4, 0.9), R.pick([WHITE, C[6], C[5]]), R.range(0.8, 1.8))
	ps.update(sdt)
	lights.update(sdt)


func drawBack(p: Px.Painter) -> void:
	# Soft vertical glow only; no floor ring, no actor afterimage.
	var g := 0.0
	if t < OUT:
		g = t / OUT
	elif t < POP + 0.3:
		g = 1.0 - Px.clamp((t - POP) / 0.3)
	p.glow(0.0, -1.0, 26.0, C[5], 0.3 * g)


func draw(p: Px.Painter) -> void:
	if t < OUT:
		var kb := t / OUT
		p.glow(mx, my, 30.0, C[5], 0.5 * kb)
		if int(t * 30.0) % 2 == 0:
			p.glow(mx, my, 12.0, C[6], 0.35 * kb)
	elif t < OUT + 0.05:
		Px.flare(p, mx, my, 14.0, 0.8, C)
		p.glow(mx, my, 40.0, C[5], 0.8)
	elif t < OUT + SQUEEZE:
		var q := Px.Ease.inCubic((t - OUT - 0.05) / (SQUEEZE - 0.05))
		var hh := (FX_HALF_H + 2.0) * (1.0 - q)
		var y := -hh - 3.0
		while y <= hh + 3.0:
			p.dot(mx, my + y, WHITE if absf(y) < hh else C[6], 1.0 if absf(y) < hh else 0.7)
			y += 1.0
		p.glow(mx, my, 34.0, C[5], 0.8)
	elif t < POP:
		var q := (t - OUT - SQUEEZE) / COLLAPSE
		var hh := (FX_HALF_H + 2.0) * (1.0 - Px.Ease.inQuad(q))
		var y := -hh - 3.0
		while y <= hh + 3.0:
			p.dot(mx, my + y, WHITE if absf(y) < hh else C[6], 1.0 if absf(y) < hh else 0.7)
			y += 1.0
		if hh > 4.0:
			y = -hh * 0.7
			while y <= hh * 0.7:
				p.dot(mx - 1.0, my + y, C[5], 0.6)
				p.dot(mx + 1.0, my + y, C[5], 0.6)
				y += 1.0
		p.glow(mx, my, 30.0, C[5], 0.9)
		p.glow(mx, my, 8.0, WHITE, 0.5)

	if t >= POP and t < POP + 0.22:
		var q := (t - POP) / 0.22
		Px.flare(p, mx, my, 22.0 * pow(1.0 - q, 1.5) + 2.0, 1.0 - q, C)
		if q < 0.3:
			p.circle(mx, my, 4.0 * (1.0 - q / 0.3) + 1.0, WHITE)
	if t > POP and t < POP + 0.3:
		Px.sparkle(p, mx, my - 1.0, 3.0, C[6], C[5], 0.3 * (1.0 - (t - POP) / 0.3))
	ps.draw(p)
	lights.draw(p)
