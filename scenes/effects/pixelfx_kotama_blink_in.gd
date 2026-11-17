# The arrival (bits converging, a line of light, a flare and sparks) is adapted from Sprite Fusion's
# open-source blink (https://www.spritefusion.com/pixel-art-vfx/movement), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/blink-in.js@ae7ec5071adacf19538e28d2d6022cd00315d1b6
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

const LINE := 0.26
const GROW := 0.1
const OPEN := 0.12
const ARRIVE := LINE + GROW + OPEN
const TIME_SCALE := 1.4 / 0.5
const FX_CENTER_Y := -22.0
const FX_HALF_H := 24.0

static var meta := {
	"name": "Kotama blink in",
	"desc": "Glittering bits spiral in to a point, open into a vertical line and burst into a bodyless flare; no actor body, no floor ring.",
	"tags": ["arcane", "blink", "teleport", "appear", "movement", "magic", "one-shot"],
	"size": [136, 96],
	"origin": [68, 80],
	"duration": 0.5,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"options": {"palette": KOTAMA_BLINK_PALETTE, "seed": 12},
}

var C: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var mx := 0.0
var my := FX_CENTER_Y
var COLS: Array
var bits: Array
var t := 0.0
var arrived := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[4]]})
	lights = Px.Lights.new()
	COLS = [WHITE, C[6], C[6], C[5], C[4]]
	bits = Px.arr(230, func(_i: int) -> Dictionary:
		var a := R.range(0.0, TAU)
		var d := R.range(16.0, 46.0)
		var ty: float = my + R.range(-FX_HALF_H, FX_HALF_H)
		var oy := sin(a) * d * 0.8 - 6.0
		if ty + oy > -2.0:
			oy = -absf(oy) - 2.0
		return {
			"tx": mx + R.range(-1.0, 1.0), "ty": ty,
			"ox": cos(a) * d, "oy": oy,
			"t0": R.range(0.0, 0.1), "t1": LINE + R.range(-0.02, GROW),
			"spin": R.range(0.8, 1.8) * R.sign(), "c": R.pick(COLS),
		}
	)


static func at(b: Dictionary, tt: float) -> Array:
	var k := Px.clamp((tt - b.t0) / (b.t1 - b.t0))
	var e := Px.Ease.outCubic(k)
	var r := 1.0 - e
	var sp: float = b.spin * r * 1.2
	var ox: float = b.ox * cos(sp) - b.oy * sin(sp)
	var oy: float = b.ox * sin(sp) + b.oy * cos(sp)
	return [b.tx + ox * r, minf(-1.0, b.ty + oy * r), k]


func update(dt: float) -> void:
	var sdt := dt * TIME_SCALE
	t += sdt
	if t < LINE and R.chance(0.6):
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
	if not arrived and t >= ARRIVE:
		arrived = true
		lights.add(mx, my - 6.0, 56.0, C[5], 0.9, 0.35)
		lights.add(mx, my, 24.0, WHITE, 0.8, 0.1)
		for i in 30:
			var a := R.range(0.0, TAU)
			var sp := R.range(35.0, 110.0)
			ps.spawn(P.STAR if R.chance(0.6) else P.MOTE, mx, my, cos(a) * sp, sin(a) * sp * 0.7 - 30.0, R.range(0.4, 0.85), R.pick(COLS), R.range(0.6, 1.6))
		for i in 12:
			var s := R.sign()
			ps.spawn(P.SPARK, mx + s * R.range(2.0, 8.0), -1.0, s * R.range(60.0, 180.0), -R.range(20.0, 110.0), R.range(0.2, 0.45))
	ps.update(sdt)
	lights.update(sdt)


func drawBack(p: Px.Painter) -> void:
	# Soft vertical glow only; no floor ring.
	var k := (t - ARRIVE + 0.03) / 0.5
	var g := 0.0
	if k >= 0.0 and k < 1.0:
		g = 1.0 - k
	elif t < ARRIVE:
		g = t / ARRIVE
	p.glow(0.0, -1.0, 26.0, C[5], 0.3 * g)


func draw(p: Px.Painter) -> void:
	# bits rushing in, streaking as they speed up, white as they land
	for b: Dictionary in bits:
		if t < b.t0 or t > b.t1 + 0.02:
			continue
		var xyk := at(b, t)
		var x: float = xyk[0]
		var y: float = xyk[1]
		var k: float = xyk[2]
		p.dot(x, y, WHITE if k > 0.75 else b.c, minf(1.0, 0.35 + k * 2.0))
		if k > 0.55:
			var pp := at(b, t - 0.015)
			p.dot((x + pp[0]) / 2.0, (y + pp[1]) / 2.0, C[5], 0.8)
		if k > 0.8:
			p.glow(x, y, 3.0, C[6], 0.3)

	if t >= LINE - 0.04 and t < LINE:
		var q := (t - LINE + 0.04) / 0.04
		Px.sparkle(p, mx, my, 2.0 + 3.0 * q, C[6], C[5], 0.6)
	elif t >= LINE and t < LINE + GROW:
		var q := Px.Ease.outCubic((t - LINE) / GROW)
		var hh := (FX_HALF_H + 3.0) * q
		var y := -hh - 2.0
		while y <= hh + 2.0:
			p.dot(mx, my + y, WHITE if absf(y) < hh else C[6], 1.0 if absf(y) < hh else 0.7)
			y += 1.0
		y = -hh * 0.7
		while y <= hh * 0.7:
			p.dot(mx - 1.0, my + y, C[5], 0.6)
			p.dot(mx + 1.0, my + y, C[5], 0.6)
			y += 1.0
		p.glow(mx, my, 30.0, C[5], 0.9)
		p.glow(mx, my, 8.0, WHITE, 0.5)
	elif t >= LINE + GROW and t < ARRIVE:
		# bodyless: the line only opens into a vertical flash, never a silhouette
		var q := Px.Ease.outCubic((t - LINE - GROW) / OPEN)
		var hh := (FX_HALF_H + 3.0) * (1.0 - 0.25 * q)
		var y := -hh
		while y <= hh:
			p.dot(mx + (-1.0 if int(y) % 4 == 0 else 0.0), my + y, WHITE, 0.85)
			y += 1.0
		p.glow(mx, my, 36.0, C[5], 0.8)

	if t >= ARRIVE and t < ARRIVE + 0.42:
		var kc := 1.0 - (t - ARRIVE) / 0.42
		p.glow(mx, my, 34.0, C[5], 0.6 * kc)

	if t >= ARRIVE and t < ARRIVE + 0.2:
		var q := (t - ARRIVE) / 0.2
		Px.flare(p, mx, my - 4.0, 18.0 * pow(1.0 - q, 1.5) + 2.0, 1.0 - q, C)
	ps.draw(p)
	lights.draw(p)
