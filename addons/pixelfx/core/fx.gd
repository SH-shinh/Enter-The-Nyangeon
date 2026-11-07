# Frames and live effect instances (src/core/fx.js): createFx, painterFor, resolveOptions, composite.
#
# An effect module is a GDScript script (see godot/docs/AUTHORING.md):
#   pure       static func draw(p, t, o) [and static func drawBack(p, t, o)]: the frame at t from t alone
#   simulated  extends core/effect.gd with func create(o) / update(dt) / draw(p) / drawBack(p) (the script is the state)
#   factory    static func create(o) -> an object with update(dt) / draw(p) / drawBack(p) (moves made with chain())
# and `static var meta := {...}`, optionally `static var act := {...}` and `static func actorAlpha(t, o)`.
# port-of: src/core/fx.js@1acacba6e8cf7c7ded76c5cfc8b02c128f8f1fc7
extends RefCounted

const Px := preload("px.gd")
const Painter := preload("painter.gd")
const Frame := preload("frame.gd")
const Actor := preload("actor.gd")

const FADE := 0.3

enum Kind { PURE, SIM, FACTORY }

## Per-script facts, found once: { kind, back (pure drawBack), alpha (actorAlpha) }.
static var _info := {}


static func info(mod: Script) -> Dictionary:
	var key := mod.resource_path if mod.resource_path else str(mod.get_instance_id())
	var hit: Variant = _info.get(key)
	if hit != null:
		return hit
	var statics := {}
	var methods := {}
	for m in mod.get_script_method_list():
		methods[m.name] = true
		if m.flags & METHOD_FLAG_STATIC:
			statics[m.name] = true
	var kind := Kind.PURE
	if statics.has("create"):
		kind = Kind.FACTORY
	elif methods.has("create"):
		kind = Kind.SIM
	var out := {"kind": kind, "back": statics.has("drawBack"), "alpha": statics.has("actorAlpha")}
	_info[key] = out
	return out


## The effect's meta with the defaults the tools assume (fps 30, bg "dark", loop false, duration 1, tags [], options {}).
static func metaOf(mod: Script) -> Dictionary:
	var m: Dictionary = mod.get("meta") if mod.get("meta") != null else {}
	var out := {"fps": 30, "bg": "dark", "loop": false, "duration": 1.0, "tags": [], "options": {}}
	out.merge(m, true)
	return out


## The effect's act (or null).
static func actOf(mod: Script) -> Variant:
	return mod.get("act")


## The painter for a frame (one per frame, reused).
static func painterFor(frame: Frame) -> Painter:
	var p: Painter = frame._painter
	if p == null:
		p = Painter.new(frame)
		frame._painter = p
	return p.reset()


static func _isRamp(v: Variant) -> bool:
	if v is PackedStringArray or v is PackedColorArray or v is PackedInt32Array:
		return v.size() > 0
	if not (v is Array) or v.is_empty():
		return false
	for c in v:
		if typeof(c) == TYPE_INT or typeof(c) == TYPE_FLOAT or typeof(c) == TYPE_COLOR:
			continue
		if typeof(c) == TYPE_STRING and String(c).begins_with("#") and String(c).length() >= 4 and String(c).length() <= 9 and String(c).substr(1).is_valid_hex_number():
			continue
		return false
	return true


## An effect's options: its defaults with the caller's on top. Any color ramp of a different length than its
## default is resampled to the default's length. Whole numbers become floats (JS has no ints), so an effect's
## arithmetic never turns into integer division; Packed arrays become Arrays.
static func resolveOptions(meta: Dictionary, o: Dictionary = {}) -> Dictionary:
	var defs: Dictionary = meta.get("options", {})
	var opts := defs.duplicate(true)
	for k in o:
		var v: Variant = o[k]
		if v is PackedStringArray or v is PackedColorArray or v is PackedInt32Array or v is PackedFloat32Array or v is PackedFloat64Array:
			v = Array(v)
		opts[k] = v
	for k in defs:
		var def: Variant = defs[k]
		if _isRamp(def) and o.has(k) and _isRamp(o[k]) and o[k].size() != def.size():
			var fitted := Px.fit(o[k], def.size())
			opts[k] = fitted.map(func(c): return Px.toHex(c))
	for k in opts:
		if typeof(opts[k]) == TYPE_INT and k != "actor":
			opts[k] = float(opts[k])
	if meta.get("actor") and not opts.get("actor"):
		opts.actor = Actor.stockActor(2 if meta.actor == 2 else 1)
	return opts


## A live instance of an effect: update(dt), draw(frame, layer), stop(), done().
static func createFx(mod: Script, o: Dictionary = {}) -> Instance:
	return Instance.new(mod, o)


class Instance:
	extends RefCounted
	var mod: Script
	var meta: Dictionary
	var options: Dictionary
	var impl: Variant = null
	var kind: int
	var back := false
	var D := 1.0
	var t := 0.0
	var stopAt := INF

	func _init(m: Script, o: Dictionary) -> void:
		mod = m
		meta = Px.Fx.metaOf(m)
		options = Px.Fx.resolveOptions(meta, o)
		var inf: Dictionary = Px.Fx.info(m)
		kind = inf.kind
		back = inf.back
		match kind:
			Px.Fx.Kind.FACTORY:
				impl = m.create(options)
			Px.Fx.Kind.SIM:
				impl = m.new()
				impl.create(options)
		D = meta.duration

	func update(dt: float) -> void:
		t += dt
		if kind == Px.Fx.Kind.PURE:
			return
		# simulations step at 120 Hz or finer whatever the caller's frame rate, so they look the same everywhere
		var n := maxi(1, ceili(dt * 120.0 - 1e-9))
		for i in n:
			impl.update(dt / n)

	func draw(frame: Px.Frame, layer: String = "") -> void:
		var p: Px.Painter = Px.Fx.painterFor(frame)
		var ox: Variant = options.get("x")
		var oy: Variant = options.get("y")
		var ang: Variant = options.get("angle")
		p.place(ox if ox != null else 0.0, oy if oy != null else 0.0, true if options.get("flip") else false, ang if ang != null else 0.0)
		p.fade = 1.0 if stopAt == INF else Px.clamp(1.0 - (t - stopAt) / Px.Fx.FADE)
		var lk: Variant = options.get("light")
		p.lightK = lk if lk != null else 1.0
		var tt := fmod(t, D) if meta.loop else minf(t, D)
		if layer != "front":
			if kind == Px.Fx.Kind.PURE:
				if back:
					p.layer = "back"
					mod.drawBack(p, tt, options)
			elif impl.has_method("drawBack"):
				p.layer = "back"
				impl.drawBack(p)
		if layer != "back":
			p.layer = "front"
			if kind == Px.Fx.Kind.PURE:
				mod.draw(p, tt, options)
			else:
				impl.draw(p)

	func _notification(what: int) -> void:
		# break the reference cycles a simulated effect may hold (see effect.gd dispose)
		if what == NOTIFICATION_PREDELETE and impl is Object and impl.has_method("dispose"):
			impl.dispose()

	## Let it end: loops fade out, one-shots cut short.
	func stop() -> void:
		if stopAt == INF:
			stopAt = t

	func done() -> bool:
		return t - stopAt >= Px.Fx.FADE or (not meta.loop and t >= D)


static func _u8(x: float) -> int:
	# Uint8ClampedArray store: clamp to 0..255, round half to even, NaN to 0
	if is_nan(x) or x <= 0.0:
		return 0
	if x >= 255.0:
		return 255
	var f := floorf(x)
	var r := x - f
	if r > 0.5 or (r == 0.5 and int(f) & 1):
		f += 1.0
	return int(f)


## Color over a background, plus light, into RGBA bytes (out: a PackedByteArray of w * h * 4, resized if needed).
## bg: null for transparent, a color number, or a PackedInt32Array of the frame's size. Over transparency, light
## becomes color with alpha (its brightest channel), which reads as additive over dark backgrounds.
static func composite(f: Frame, out: PackedByteArray, bg: Variant = null, lightK: float = 1.0) -> PackedByteArray:
	var n := f.w * f.h
	if out.size() != n * 4:
		out.resize(n * 4)
	var C := f.color
	var L := f.light
	var flat := typeof(bg) == TYPE_INT
	var none := bg == null
	for i in n:
		var c := C[i]
		var l := L[i] & 0xffffff
		var r: float
		var g: float
		var b: float
		var a: float
		var ca := (c >> 24) & 255
		if ca == 255:
			r = c & 255
			g = (c >> 8) & 255
			b = (c >> 16) & 255
			a = 255.0
		elif none:
			# translucent color over nothing keeps its alpha
			r = c & 255
			g = (c >> 8) & 255
			b = (c >> 16) & 255
			a = ca
		else:
			var k: int = bg if flat else bg[i]
			var fa := ca / 255.0
			r = (c & 255) * fa + (k & 255) * (1.0 - fa)
			g = ((c >> 8) & 255) * fa + ((k >> 8) & 255) * (1.0 - fa)
			b = ((c >> 16) & 255) * fa + ((k >> 16) & 255) * (1.0 - fa)
			a = 255.0
		if l:
			var lr := (l & 255) * lightK
			var lg := ((l >> 8) & 255) * lightK
			var lb := ((l >> 16) & 255) * lightK
			if a < 255.0:
				# over transparency: premultiply what's there, add the light, divide by the new alpha
				var pa := a / 255.0
				var pr := r * pa + lr
				var pg := g * pa + lg
				var pb := b * pa + lb
				var na := minf(1.0, maxf(pa, maxf(lr, maxf(lg, lb)) / 255.0))
				if na > 0.0:
					r = minf(255.0, pr / na)
					g = minf(255.0, pg / na)
					b = minf(255.0, pb / na)
					a = na * 255.0
			else:
				r = minf(255.0, r + lr)
				g = minf(255.0, g + lg)
				b = minf(255.0, b + lb)
		var j := i * 4
		out[j] = _u8(r)
		out[j + 1] = _u8(g)
		out[j + 2] = _u8(b)
		out[j + 3] = _u8(a)
	return out
