# Moves: several effects played as one. A cue says which effect, when, where and for how long; a projectile is just an
# effect whose x is a function of time. It's an ordinary effect from the outside: it plays, recolors and exports.
#
#   static var CHAIN := Px.chain([
#       {"fx": Charge, "t": 0.08, "until": THROW, "palette": Px.PAL.fire},
#       {"fx": Fireball, "t": THROW, "until": HIT, "x": func(t): return 28.0 + (t - THROW) * SPEED, "y": -22.0},
#   ])
#   static func create(o: Dictionary): return CHAIN.create(o)
# port-of: src/core/chain.js@c816e89170277c16d2820548c2b31ace6f797e0d
extends RefCounted

const Px := preload("px.gd")
const CUE_KEYS := ["fx", "t", "until", "x", "y", "flip"]


## create(o) for a list of cues: { fx (an effect script), t (when it starts), until (cut it off here), x, y (numbers,
## or Callables of the move's time, local space), flip, ...any of that effect's options }.
static func chain(cues: Array) -> Factory:
	return Factory.new(cues)


class Factory:
	extends RefCounted
	var cues: Array

	func _init(list: Array) -> void:
		cues = list

	func create(o: Dictionary) -> Chained:
		return Chained.new(cues, o)


class Chained:
	extends RefCounted
	var list: Array = []
	var t := 0.0

	func _init(cues: Array, o: Dictionary) -> void:
		var seed: float = o.seed if o.get("seed") != null else 1.0
		for i in cues.size():
			var c: Dictionary = cues[i]
			var opts := {}
			for k in c:
				if not (k in Px.Chain.CUE_KEYS):
					opts[k] = c[k]
			opts.seed = seed + i
			list.append({
				"fx": c.fx,
				"t": c.t if c.get("t") != null else 0.0,
				"until": c.until if c.get("until") != null else INF,
				"x": c.x if c.get("x") != null else 0.0,
				"y": c.y if c.get("y") != null else 0.0,
				"flip": true if c.get("flip") else false,
				"opts": opts, "inst": null, "over": false,
			})

	func _at(v: Variant) -> float:
		return v.call(t) if v is Callable else v

	func update(dt: float) -> void:
		t += dt
		for c in list:
			if c.over or t < c.t:
				continue
			if c.inst == null:
				c.inst = Px.Fx.createFx(c.fx, c.opts)
			else:
				c.inst.update(dt)
			if t >= c.until or (c.inst.done() and not Px.Fx.metaOf(c.fx).loop):
				c.over = true

	func _each(p: Variant, layer: String) -> void:
		var frame: Px.Frame = p.frame
		var tx: float = p.tx
		var ty: float = p.ty
		var sign: float = p.fx
		var cs: float = p.cs
		var sn: float = p.sn
		var fade: float = p.fade
		var lightK: float = p.lightK
		for c in list:
			if c.inst == null or c.over:
				continue
			c.inst.options.x = tx + sign * _at(c.x)
			c.inst.options.y = ty + _at(c.y)
			c.inst.options.flip = (sign < 0.0) != c.flip
			c.inst.draw(frame, layer)
		# each one places the painter for itself: put it back for whoever draws next
		p.tx = tx
		p.ty = ty
		p.fx = sign
		p.cs = cs
		p.sn = sn
		p.fade = fade
		p.lightK = lightK

	func drawBack(p: Variant) -> void:
		_each(p, "back")

	func draw(p: Variant) -> void:
		_each(p, "front")


## Reuse an act's keys in a longer move: later by dt, moved along by dx, with anything else laid over each pose.
static func shiftKeys(keys: Array, dt: float, over: Dictionary = {}) -> Array:
	var dx: float = over.get("dx", 0.0)
	var rest := over.duplicate()
	rest.erase("dx")
	var out := []
	for k in keys:
		var pose: Dictionary = (k[1] as Dictionary).duplicate()
		pose.merge(rest, true)
		pose.x = (k[1].x if k[1].get("x") != null else 0.0) + dx
		var key := [k[0] + dt, pose]
		key.append(k[2] if k.size() > 2 else null)
		out.append(key)
	return out


## The same for hits.
static func shiftHits(hits: Array, dt: float) -> Array:
	var out := []
	for h in hits:
		var c: Dictionary = (h as Dictionary).duplicate()
		c.t = h.t + dt
		out.append(c)
	return out
