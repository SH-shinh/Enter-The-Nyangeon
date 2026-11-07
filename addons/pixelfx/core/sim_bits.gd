# Rigid debris that tumbles, bounces and settles (JS `new Bits(opts)` from src/core/sim.js). opts: { ground }.
# add({ kind, x, y, vx, vy, a, va, s (size), c (color), ramp (chunk shading, dark to bright), g (gravity scale),
# drag, bounce, life }); update(dt); draw(p). Bits are Dictionaries, so effects may add their own fields.
# port-of: src/core/sim.js@68f1a7097a6cf263b03d61a5144cfdb3938e4850 (class Bits)
extends RefCounted

const Px := preload("px.gd")
const Sim := preload("sim.gd")
const B := Sim.B
const GRAVITY := Sim.GRAVITY
const WHITE := -1

var list: Array = []
var ground: Variant = null
var _gn := 0
var count: int:
	get: return list.size()


func _init(opts: Dictionary = {}) -> void:
	ground = opts.get("ground")
	_gn = ground.get_argument_count() if ground is Callable else 0


func _floor(x: float) -> float:
	if ground == null:
		return INF
	return ground.call(x) if _gn >= 1 else ground.call()


func add(b: Dictionary) -> void:
	var life: float = b.life if b.get("life") != null else 1.0
	var o := {"kind": B.SHARD, "vx": 0.0, "vy": 0.0, "a": 0.0, "va": 0.0, "s": 1.0, "c": WHITE, "g": 1.0, "drag": 0.0, "bounce": 0.0, "rest": false}
	o.merge(b, true)
	o.life = life
	o.max = life
	list.append(o)


func update(dt: float) -> void:
	var i := list.size() - 1
	while i >= 0:
		var idx := i
		i -= 1
		var b: Dictionary = list[idx]
		b.life -= dt
		if b.life <= 0.0:
			list.remove_at(idx)
			continue
		if b.rest:
			continue
		b.vy += GRAVITY * b.g * dt
		b.vx -= b.vx * b.drag * dt
		b.vy -= b.vy * b.drag * dt
		b.x += b.vx * dt
		b.y += b.vy * dt
		b.a += b.va * dt
		var fl := _floor(b.x)
		var sp: float = b.vy
		if b.g <= 0.0 or b.y < fl or sp <= 0.0:
			continue
		b.y = fl - 0.01
		if b.kind == B.DRIP:
			b.life = 0.0
		elif b.bounce > 0.0 and sp > 70.0:
			b.vy = -sp * b.bounce
			b.vx *= 0.7
			b.va *= 0.6
		else:
			b.rest = true
			b.vx = 0.0
			b.vy = 0.0


func draw(p: Variant) -> void:
	for b: Dictionary in list:
		var a := minf(1.0, b.life / 0.4)
		var ca := cos(b.a)
		var sa := sin(b.a)
		if b.kind == B.SHARD:
			var half: float = b.s / 2.0
			var d := -half
			var c := Px.hex(b.c)
			while d <= half:
				p.dot(b.x + ca * d, b.y + sa * d, WHITE if d > half - 0.6 else c, a)
				d += 0.5
		elif b.kind == B.DRIP:
			p.dot(b.x, b.y, Px.hex(b.c), a)
			p.dot(b.x, b.y - 1.0, Px.hex(b.c), a * 0.5)
		else:
			# a shaded chunk: lit top-left, dark bottom-right, a dark rim
			var R := Px.ramp(b.ramp if b.get("ramp") != null else Sim.CHUNK_RAMP)
			var n := R.size()
			var x := Px.round(b.x)
			var y := Px.round(b.y)
			var r := ceili(b.s) + 1
			var s: float = b.s
			for py in range(-r, r + 1):
				for px in range(-r, r + 1):
					var u := (px + 0.5) * ca + (py + 0.5) * sa
					var v := -(px + 0.5) * sa + (py + 0.5) * ca
					var d := absf(u) / s + absf(v) / (s * 0.62)
					if d > 1.3:
						continue
					p.dot(x + px, y + py, R[0] if d > 1.0 else ((R[n - 1] if u < 0.0 else R[n - 2]) if v < 0.0 else (R[n - 3] if u < 0.0 else R[maxi(1, n - 4)])), a)
