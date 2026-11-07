# pixelfx core: everything an effect uses, as `Px.<name>` (the GDScript side of src/core/index.js).
#
# The pure helpers effects call per pixel live here directly, so nothing forwards:
#   math.js (numbers, easing, hash, noise), color.js (colors, ramps, PAL), particles.js (closed-form particles),
#   shapes.js (bolts, stars, polygons, trails) and the drawing helpers of sim.js (sparkle, flare, band, crystal).
# Classes and the rest of the core are constants pointing at their own scripts.
#
# Numbers follow JavaScript exactly where it matters for identical pixels: see godot/docs/PORTING.md.
# port-of: src/core/index.js@14b3144cb33068271221f1766994b627660d5d93
# port-of: src/core/math.js@90356680e4696072b6fc8faedcc9ac15ef42ae9d
# port-of: src/core/color.js@60cdedd3352b3a682ef0391f4b3957918b5756d3
# port-of: src/core/particles.js@345c67fbea7cfa5f03e1591bb428a18abdd0263b
# port-of: src/core/shapes.js@a59200b40f137b5852b1f8917dc6c7209f6ffe45
extends RefCounted

const Self := preload("px.gd")
const Rng := preload("rng.gd")
const Ease := preload("ease.gd")
const Painter := preload("painter.gd")
const Fx := preload("fx.gd")
const Frame := preload("frame.gd")
const Sim := preload("sim.gd")
const Particles := preload("sim_particles.gd")
const Bits := preload("sim_bits.gd")
const Lights := preload("sim_lights.gd")
const Blazes := preload("sim_blazes.gd")
const Effect := preload("effect.gd")
const PixelFont := preload("font.gd")
const Actor := preload("actor.gd")
const Scene := preload("scene.gd")
const Chain := preload("chain.gd")
const Poses := preload("poses.gd")
const Act := preload("act.gd")
const Rig := preload("rig.gd")
const Sorter := preload("sort.gd")

const M32 := 0xFFFFFFFF
const INV32 := 1.0 / 4294967296.0
## A default-argument marker no caller passes: lets rand()/hash() take 1 to 6 numbers like JS rest params.
const NA := -9.8765432123e306

# ---------------------------------------------------------------------------------------------------- math.js

static func clamp(x: float, a: float = 0.0, b: float = 1.0) -> float:
	return a if x < a else (b if x > b else x)

static func lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t

static func invLerp(a: float, b: float, x: float) -> float:
	return 0.0 if b == a else (x - a) / (b - a)

static func remap(x: float, a0: float, a1: float, b0: float, b1: float) -> float:
	return Self.lerp(b0, b1, Self.invLerp(a0, a1, x))

static func fract(x: float) -> float:
	return x - floorf(x)

## JS ((x % m) + m) % m with float %.
static func wrap(x: float, m: float) -> float:
	return fmod(fmod(x, m) + m, m)

## Progress 0..1 of t through the window [t0, t1]: 0 before it, 1 after it.
static func seg(t: float, t0: float, t1: float) -> float:
	return Self.clamp((t - t0) / (t1 - t0))

## Hermite smoothstep of x between e0 and e1.
static func smooth(e0: float, e1: float, x: float) -> float:
	var t := Self.clamp((x - e0) / (e1 - e0))
	return t * t * (3.0 - 2.0 * t)

## 0 -> 1 -> 0 over the window [t0, t1] (sine bump).
static func bump(t: float, t0: float, t1: float) -> float:
	return 0.0 if (t <= t0 or t >= t1) else sin(PI * Self.seg(t, t0, t1))

static func pingpong(x: float) -> float:
	return 1.0 - absf(Self.wrap(x, 2.0) - 1.0)

static func dist(x0: float, y0: float, x1: float, y1: float) -> float:
	return Self.hypot(x1 - x0, y1 - y0)

static func angleTo(x0: float, y0: float, x1: float, y1: float) -> float:
	return atan2(y1 - y0, x1 - x0)

## JS Math.round: halves go up (towards +infinity), unlike GDScript round().
static func round(x: float) -> float:
	var r := ceilf(x)
	if r - 0.5 > x:
		r -= 1.0
	return r

## JS Math.round as an int (for indices).
static func roundi(x: float) -> int:
	return int(Self.round(x))

## JS Math.hypot, V8's algorithm (normalised, Kahan-compensated): bit-identical results.
static func hypot(a: float, b: float, c: float = NA) -> float:
	a = absf(a)
	b = absf(b)
	var three := c != NA
	if three:
		c = absf(c)
	if is_nan(a) or is_nan(b) or (three and is_nan(c)):
		if is_inf(a) or is_inf(b) or (three and is_inf(c)):
			return INF
		return NAN
	var mx := a if a > b else b
	if three and c > mx:
		mx = c
	if is_inf(mx):
		return INF
	if mx == 0.0:
		return 0.0
	var sum := 0.0
	var comp := 0.0
	var n := a / mx
	var summand := n * n - comp
	var pre := sum + summand
	comp = (pre - sum) - summand
	sum = pre
	n = b / mx
	summand = n * n - comp
	pre = sum + summand
	comp = (pre - sum) - summand
	sum = pre
	if three:
		n = c / mx
		summand = n * n - comp
		pre = sum + summand
		comp = (pre - sum) - summand
		sum = pre
	return sqrt(sum) * mx

static var _w := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0])

static func _bits(x: float) -> int:
	_w.encode_double(0, x)
	return _w.decode_s64(0)

static func _dbl(b: int) -> float:
	_w.encode_s64(0, b)
	return _w.decode_double(0)

## JS Math.cbrt, bit for bit: fdlibm's cbrt as V8 has it (src/base/ieee754.cc).
static func cbrt(x: float) -> float:
	var B1 := 715094163
	var B2 := 696219795
	var P0 := 1.87595182427177009643
	var P1 := -1.88497979543377169875
	var P2 := 1.621429720105354466140
	var P3 := -0.758397934778766047437
	var P4 := 0.145996192886612446982
	var xb := _bits(x)
	var hx := (xb >> 32) & 0xFFFFFFFF
	var low := xb & 0xFFFFFFFF
	var sgn := hx & 0x80000000
	hx ^= sgn
	if hx >= 0x7ff00000:
		return x + x
	var t := 0.0
	if hx < 0x00100000:
		if (hx | low) == 0:
			return x
		t = _dbl(0x43500000 << 32)
		t *= x
		var high := (_bits(t) >> 32) & 0xFFFFFFFF
		t = _dbl((sgn | (floori((high & 0x7fffffff) / 3.0) + B2)) << 32)
	else:
		t = _dbl((sgn | (floori(hx / 3.0) + B1)) << 32)
	var r := (t * t) * (t / x)
	t = t * ((P0 + r * (P1 + r * P2)) + ((r * r) * r) * (P3 + r * P4))
	t = _dbl((_bits(t) + 0x80000000) & ~0x3fffffff)
	var s := t * t
	r = x / s
	var w := t + t
	r = (r - t) / (w + r)
	t = t + t * r
	return t

## JS Math.exp, bit for bit: fdlibm's exp as V8 has it (src/base/ieee754.cc), for every result that isn't subnormal.
## The built-in exp() is the C library's and differs in the last bit for a few inputs; use this where it matters.
static func exp(x: float) -> float:
	var halF := [0.5, -0.5]
	var ln2HI := [6.93147180369123816490e-01, -6.93147180369123816490e-01]
	var ln2LO := [1.90821492927058770002e-10, -1.90821492927058770002e-10]
	var invln2 := 1.44269504088896338700e+00
	var P1 := 1.66666666666666019037e-01
	var P2 := -2.77777777770155933842e-03
	var P3 := 6.61375632143793436117e-05
	var P4 := -1.65339022054652515390e-06
	var P5 := 4.13813679705723846039e-08
	var bits := _bits(x)
	var hx := (bits >> 32) & 0xFFFFFFFF
	var xsb := (hx >> 31) & 1
	hx &= 0x7fffffff
	var hi := 0.0
	var lo := 0.0
	var k := 0
	if hx >= 0x40862E42:
		if hx >= 0x7ff00000:
			if ((hx & 0xfffff) | (bits & 0xFFFFFFFF)) != 0:
				return x + x
			return x if xsb == 0 else 0.0
		if x > 7.09782712893383973096e+02:
			return INF
		if x < -7.45133219101941108420e+02:
			return 0.0
	if hx > 0x3fd62e42:
		if hx < 0x3FF0A2B2:
			if x == 1.0:
				return 2.718281828459045
			hi = x - ln2HI[xsb]
			lo = ln2LO[xsb]
			k = 1 - xsb - xsb
		else:
			k = int(invln2 * x + halF[xsb])
			var t := float(k)
			hi = x - t * ln2HI[0]
			lo = t * ln2LO[0]
		x = hi - lo
	elif hx < 0x3e300000:
		return 1.0 + x
	else:
		k = 0
	var t2 := x * x
	var twopk := _dbl((0x3ff00000 + (k << 20)) << 32) if k >= -1021 else _dbl((0x3ff00000 + ((k + 1000) << 20)) << 32)
	var c := x - t2 * (P1 + t2 * (P2 + t2 * (P3 + t2 * (P4 + t2 * P5))))
	if k == 0:
		return 1.0 - ((x * c) / (c - 2.0) - x)
	var y := 1.0 - ((lo - (x * c) / (2.0 - c)) - hi)
	if k >= -1021:
		if k == 1024:
			return y * 2.0 * _dbl(0x7fe00000 << 32)
		return y * twopk
	# 2^-1000 from its bits: GDScript's parser doesn't read literals this small exactly
	return y * twopk * _dbl(0x01700000 << 32)


## JS Math.log2 (C library log, so it may differ from V8 in the last bit).
static func log2(x: float) -> float:
	return log(x) / log(2.0)

## JS Math.sign (0 stays 0).
static func sign(x: float) -> float:
	return 1.0 if x > 0.0 else (-1.0 if x < 0.0 else x)

## JS ToInt32 (`x | 0`): truncate, wrap to a signed 32-bit int.
static func i32(v: Variant) -> int:
	var u := Rng.u32(v)
	return u - 0x100000000 if u >= 0x80000000 else u

## JS ToUint32 (`x >>> 0`).
static func u32(v: Variant) -> int:
	return Rng.u32(v)

## Math.imul, returned as a signed 32-bit int like JS.
static func imul(a: Variant, b: Variant) -> int:
	return Self.i32(Rng.imul(Rng.u32(a), Rng.u32(b)))

static func _mix(h: int, n: Variant) -> int:
	var u: int
	if typeof(n) == TYPE_INT:
		u = n & M32
	else:
		var f: float = n
		# ToInt32 is truncation then the low 32 bits: int() and & do exactly that while it fits (NaN and inf give 0)
		u = (int(f) & M32) if (absf(f) < 9.0e18 or is_nan(f)) else Rng.u32(f)
	var x := h ^ u
	h = ((x * 0xca6b) + (((x * 0x85eb) & 0xFFFF) << 16)) & M32
	h ^= h >> 13
	h = ((h * 0xae35) + (((h * 0xc2b2) & 0xFFFF) << 16)) & M32
	h ^= h >> 16
	return h

## 32-bit integer hash of 1 to 6 numbers (unsigned, like JS `>>> 0`).
static func hash(a: Variant, b: Variant = NA, c: Variant = NA, d: Variant = NA, e: Variant = NA, f: Variant = NA) -> int:
	var h := _mix(0x9e3779b9, a)
	if typeof(b) == TYPE_FLOAT and b == NA:
		return h
	h = _mix(h, b)
	if typeof(c) == TYPE_FLOAT and c == NA:
		return h
	h = _mix(h, c)
	if typeof(d) == TYPE_FLOAT and d == NA:
		return h
	h = _mix(h, d)
	if typeof(e) == TYPE_FLOAT and e == NA:
		return h
	h = _mix(h, e)
	if typeof(f) == TYPE_FLOAT and f == NA:
		return h
	return _mix(h, f)

## rand(a, b, c) for the noise lattice, typed and written out: the same hash, without the Variant checks.
static func _rand3(a: float, b: float, c: float) -> float:
	var h := 0x9e3779b9
	var u: int
	var x: int
	u = (int(a) & M32) if (absf(a) < 9.0e18 or is_nan(a)) else Rng.u32(a)
	x = h ^ u
	h = ((x * 0xca6b) + (((x * 0x85eb) & 0xFFFF) << 16)) & M32
	h ^= h >> 13
	h = ((h * 0xae35) + (((h * 0xc2b2) & 0xFFFF) << 16)) & M32
	h ^= h >> 16
	u = (int(b) & M32) if (absf(b) < 9.0e18 or is_nan(b)) else Rng.u32(b)
	x = h ^ u
	h = ((x * 0xca6b) + (((x * 0x85eb) & 0xFFFF) << 16)) & M32
	h ^= h >> 13
	h = ((h * 0xae35) + (((h * 0xc2b2) & 0xFFFF) << 16)) & M32
	h ^= h >> 16
	u = (int(c) & M32) if (absf(c) < 9.0e18 or is_nan(c)) else Rng.u32(c)
	x = h ^ u
	h = ((x * 0xca6b) + (((x * 0x85eb) & 0xFFFF) << 16)) & M32
	h ^= h >> 13
	h = ((h * 0xae35) + (((h * 0xc2b2) & 0xFFFF) << 16)) & M32
	h ^= h >> 16
	return h * INV32


## Deterministic random number in [0, 1) from 1 to 6 numbers (seed, particle index, which value...).
static func rand(a: Variant, b: Variant = NA, c: Variant = NA, d: Variant = NA, e: Variant = NA, f: Variant = NA) -> float:
	return Self.hash(a, b, c, d, e, f) * INV32

## A generator for one particle: rng(seed, i) gives the same numbers every frame.
static func rng(a: Variant, b: Variant = NA, c: Variant = NA, d: Variant = NA, e: Variant = NA, f: Variant = NA) -> Rng:
	return Rng.new(Self.hash(a, b, c, d, e, f))

## Smooth 1D value noise in [-1, 1].
static func noise(x: float, seed: Variant = 0) -> float:
	var i := floorf(x)
	var fx := x - i
	var u := fx * fx * (3.0 - 2.0 * fx)
	return Self.lerp(Self.rand(i, seed), Self.rand(i + 1.0, seed), u) * 2.0 - 1.0

## Smooth 2D value noise in [-1, 1].
static func noise2(x: float, y: float, seed: Variant = 0) -> float:
	var ix := floorf(x)
	var iy := floorf(y)
	var fx := x - ix
	var fy := y - iy
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	var sd: float = seed
	var a := _rand3(ix, iy, sd)
	var b := _rand3(ix + 1.0, iy, sd)
	var c := _rand3(ix, iy + 1.0, sd)
	var d := _rand3(ix + 1.0, iy + 1.0, sd)
	return Self.lerp(Self.lerp(a, b, ux), Self.lerp(c, d, ux), uy) * 2.0 - 1.0

## Fractal 2D noise in about [-1, 1].
static func fbm(x: float, y: float, seed: float = 0.0, octaves: float = 3) -> float:
	var s := 0.0
	var a := 0.5
	var n := 0.0
	for o in int(octaves):
		s += Self.noise2(x, y, seed + o * 101) * a
		n += a
		x *= 2.03
		y *= 2.03
		a *= 0.5
	return s / n

## 2D value noise whose lattice repeats every px cells in x and py cells in y (0: no repeat).
static func tileNoise(x: float, y: float, px: float = 0.0, py: float = 0.0, seed: Variant = 0) -> float:
	var ix := floorf(x)
	var iy := floorf(y)
	var fx := x - ix
	var fy := y - iy
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	var x0 := Self.wrap(ix, px) if px else ix
	var x1 := Self.wrap(ix + 1.0, px) if px else ix + 1.0
	var y0 := Self.wrap(iy, py) if py else iy
	var y1 := Self.wrap(iy + 1.0, py) if py else iy + 1.0
	var sd: float = seed
	var a := _rand3(x0, y0, sd)
	var b := _rand3(x1, y0, sd)
	var c := _rand3(x0, y1, sd)
	var d := _rand3(x1, y1, sd)
	return Self.lerp(Self.lerp(a, b, ux), Self.lerp(c, d, ux), uy) * 2.0 - 1.0

## Fractal tileNoise: every octave keeps the repeat, so scrolled fields still loop.
static func tileFbm(x: float, y: float, px: float = 0.0, py: float = 0.0, seed: float = 0.0, octaves: float = 3) -> float:
	var s := 0.0
	var a := 0.5
	var n := 0.0
	var k := 1.0
	for o in int(octaves):
		s += tileNoise(x * k, y * k, px * k, py * k, seed + o * 101) * a
		n += a
		a *= 0.5
		k *= 2.0
	return s / n

## Noise that loops: the same value at phase 0 and phase 1 (for seamless loops).
static func loopNoise(phase: float, radius: float = 1.0, seed: Variant = 0) -> float:
	var a := phase * TAU
	return Self.noise2(cos(a) * radius + 50.0, sin(a) * radius + 50.0, seed)

# --------------------------------------------------------------------------------------------------- color.js
# Colors are 32-bit ints laid out like RGBA bytes (R in the low byte), as JS: rgb() and hex() are *signed*
# (opaque colors are negative), frame buffers hold the same bits. Read a buffer with `& 0xFFFFFFFF` where JS
# compares against a Uint32Array value.

static func rgb(r: float, g: float, b: float) -> int:
	# int() truncates like JS ToInt32 and `& 255` only keeps the low byte, so this is exact for any finite value
	return -16777216 | ((int(b) & 255) << 16) | ((int(g) & 255) << 8) | (int(r) & 255)

static func red(c: int) -> int:
	return c & 255

static func green(c: int) -> int:
	return (c >> 8) & 255

static func blue(c: int) -> int:
	return (c >> 16) & 255

static func alpha(c: int) -> int:
	return (c >> 24) & 255

## "#rgb" or "#rrggbb" (or a color number, passed through, or a Godot Color) to a color number.
static func hex(h: Variant) -> int:
	match typeof(h):
		TYPE_INT:
			return h
		TYPE_FLOAT:
			return Self.i32(h)
		TYPE_COLOR:
			var col: Color = h
			return Self.rgb(col.r8, col.g8, col.b8)
	var s: String = String(h).replace("#", "")
	if s.length() == 3:
		s = s[0] + s[0] + s[1] + s[1] + s[2] + s[2]
	var v := s.substr(0, 6).hex_to_int()
	return Self.rgb((v >> 16) & 255, (v >> 8) & 255, v & 255)

static func toHex(c: int) -> String:
	return "#%02x%02x%02x" % [red(c), green(c), blue(c)]

## Linear mix of two colors.
static func mix(a: int, b: int, t: float) -> int:
	t = Self.clamp(t)
	return Self.rgb(red(a) + (red(b) - red(a)) * t, green(a) + (green(b) - green(a)) * t, blue(a) + (blue(b) - blue(a)) * t)

## Multiply a color's brightness by k.
static func scale(c: int, k: float) -> int:
	return Self.rgb(minf(255.0, red(c) * k), minf(255.0, green(c) * k), minf(255.0, blue(c) * k))

## Perceived brightness 0..1.
static func luma(c: int) -> float:
	return (0.299 * red(c) + 0.587 * green(c) + 0.114 * blue(c)) / 255.0

## A list of hex strings (dark to bright) to color numbers.
static func ramp(list: Variant) -> Array:
	var out := []
	for v in list:
		out.append(Self.hex(v))
	return out

## Resample a ramp to exactly n steps, keeping its ends.
static func fit(r: Variant, n: int) -> Array:
	var m := Self.ramp(r)
	if m.size() == n:
		return m
	var out := []
	for i in n:
		out.append(m[roundi((i * (m.size() - 1)) / float(maxi(1, n - 1)))])
	return out

## The ramp step for t in 0..1, no blending.
static func at(r: Array, t: float) -> int:
	return r[int(Self.clamp(floorf(t * r.size()), 0.0, r.size() - 1.0))]

## Blended color along a ramp (for light, where smooth is right).
static func blend(r: Array, t: float) -> int:
	var x := Self.clamp(t) * (r.size() - 1)
	var i := mini(r.size() - 2, floori(x))
	return Self.mix(r[i], r[i + 1], x - i)

## Hue-shifted ramps, dark to bright. Effects take `palette` as an option, so any of these can recolor them.
const PAL := {
	"fire": ["#1f0b10", "#4a1118", "#8c1d1c", "#cc3a1a", "#f2701f", "#ffae35", "#ffe27a", "#fff8d6"],
	"ember": ["#1a0a0e", "#3d1012", "#701a14", "#a8301a", "#e0561e", "#ff8a2a", "#ffc46a"],
	"lava": ["#14060a", "#380a10", "#6e1210", "#ac2410", "#e8501a", "#ff8c2a", "#ffd25a"],
	"smoke": ["#0e0c12", "#1d1a22", "#2e2a35", "#433e4b", "#5c5664", "#7b7484", "#a39cab"],
	"dust": ["#1c1610", "#33281c", "#4f3f2c", "#6e5a40", "#927a58", "#b89f78", "#dcc8a2"],
	"ice": ["#0c1430", "#162c5c", "#1f4f94", "#2f7fcc", "#58b4ec", "#9bdcff", "#d8f4ff", "#ffffff"],
	"water": ["#081830", "#0e2e5a", "#14508c", "#1c76bc", "#36a2e0", "#78ccf4", "#c4ecff", "#ffffff"],
	"electric": ["#0a0f2e", "#172a78", "#2550d0", "#3f8cff", "#7cc8ff", "#c8f0ff", "#ffffff"],
	"volt": ["#24160a", "#5e3a0c", "#a8680f", "#e8a218", "#ffd23c", "#fff08a", "#ffffff"],
	"poison": ["#0d1a0c", "#173a14", "#265e18", "#3f8a1e", "#6cb82a", "#a8e04a", "#e0ff8a"],
	"holy": ["#2a1c08", "#5a3e10", "#9a6c18", "#d8a428", "#ffd84a", "#fff09a", "#fffbe6", "#ffffff"],
	"heal": ["#08201a", "#0f3f2c", "#17663e", "#24924e", "#3ec466", "#7ee88a", "#c8ffc4", "#ffffff"],
	"arcane": ["#140a26", "#2b1252", "#481c88", "#6b2cc0", "#9a48ec", "#c684ff", "#ecc8ff", "#ffffff"],
	"shadow": ["#050308", "#0f0a18", "#1c1230", "#2c1a4a", "#432468", "#5e3290", "#8048b8", "#a970e0"],
	"blood": ["#14040a", "#3a0a14", "#6a101c", "#a01824", "#d42a30", "#ff5a50", "#ff9a8a"],
	"earth": ["#140e0a", "#2a1e14", "#47321e", "#69492a", "#8e6638", "#b88a52", "#dcb47c"],
	"stone": ["#0e0e12", "#1c1c24", "#2c2c38", "#42424f", "#5c5c6b", "#7d7d8c", "#a4a4b2", "#d0d0da"],
	"gold": ["#1e1206", "#4a2c08", "#86520c", "#c48412", "#f0b424", "#ffe066", "#fff6c4", "#ffffff"],
	"leaf": ["#0c1a0e", "#163418", "#225224", "#357530", "#4f9a3a", "#7cc048", "#b4e070", "#e4ffb0"],
	"wood": ["#160c06", "#2e1a0c", "#4a2c14", "#6a421e", "#8e5c2c", "#b47c40", "#d8a464"],
	"metal": ["#0c0e14", "#1c2230", "#2e3648", "#4a5468", "#6e7a90", "#9aa6ba", "#d0d8e6", "#ffffff"],
	"bone": ["#1a1814", "#3a352c", "#5e5648", "#8a806c", "#b8ad96", "#e4dcc8", "#fffaf0"],
	"neon": ["#1a0516", "#3d0a33", "#701560", "#b0228f", "#f53cd1", "#ff86e6", "#ffd2f6", "#ffffff"],
	"cyber": ["#041418", "#08303a", "#0c5260", "#108088", "#18b4b0", "#4ce8d8", "#b4fff0", "#ffffff"],
	"matrix": ["#020a04", "#05200c", "#0a3c16", "#106624", "#1a9a34", "#3cd650", "#a4ffa8", "#e8ffe8"],
	"candy": ["#ff4a5a", "#ff9a2a", "#ffe03c", "#5ad84a", "#3cc8ff", "#7a6cff", "#f53cd1"],
	"night": ["#07060d", "#0c0a18", "#131026", "#1b1734", "#241f44", "#2f2956"],
}

## The same ramps as color numbers.
static var RAMP := _ramps()

static func _ramps() -> Dictionary:
	var out := {}
	for k in PAL:
		out[k] = Self.ramp(PAL[k])
	return out

const WHITE := -1  # Self.hex("#ffffff")
const BLACK := -16777216  # Self.hex("#000000")
const INK := -15726069  # hex("#0b0a10")
const PATCH := -3064587  # hex("#f53cd1")

# ----------------------------------------------------------------------------------------------- particles.js
# Particles without a simulation: each one's position is a closed-form function of its age.

## Where a particle is after t seconds, launched from (x, y) at (vx, vy) px/s, under gravity g and linear drag.
## (Its exp is V8's, bit for bit: a drifting puff's position can land on a pixel boundary.)
## Returns [x, y].
static func fly(x: float, y: float, vx: float, vy: float, t: float, g: float = 0.0, drag: float = 0.0) -> Array:
	if drag <= 0.0:
		return [x + vx * t, y + vy * t + 0.5 * g * t * t]
	var f := (1.0 - Self.exp(-drag * t)) / drag
	var vt := g / drag
	return [x + vx * f, y + vt * t + (vy - vt) * f]

## Its velocity at t. Returns [vx, vy].
static func flyV(vx: float, vy: float, t: float, g: float = 0.0, drag: float = 0.0) -> Array:
	if drag <= 0.0:
		return [vx, vy + g * t]
	var e := Self.exp(-drag * t)
	var vt := g / drag
	return [vx * e, vt + (vy - vt) * e]

## Calls fn with as many of (a, b, c, d) as it declares: JS callbacks may take fewer arguments than they're given.
static func call4(fn: Callable, n: int, a: Variant, b: Variant = null, c: Variant = null, d: Variant = null) -> Variant:
	match n:
		0: return fn.call()
		1: return fn.call(a)
		2: return fn.call(a, b)
		3: return fn.call(a, b, c)
	return fn.call(a, b, c, d)

## n one-shot particles: fn.call(r, i) with a repeatable rng per particle.
static func burst(n: float, seed: Variant, fn: Callable) -> void:
	var na := fn.get_argument_count()
	var i := 0
	while i < n:
		call4(fn, na, rng(seed, i), i)
		i += 1

## Particles that repeat every `period` seconds, for loops with no seam: fn.call(age, life, r, i) for every live copy.
## life is a number or a Callable taking the particle's rng.
static func cycle(t: float, period: float, count: float, seed: Variant, life: Variant, fn: Callable) -> void:
	var na := fn.get_argument_count()
	var i := 0
	while i < count:
		var g := rng(seed, i, 911)
		var born := g.next() * period
		var L: float = life.call(g) if life is Callable else life
		var age := fmod(fmod(t - born, period) + period, period)
		while age < L:
			call4(fn, na, age, L, rng(seed, i), i)
			age += period
		i += 1

## Particles born at a steady rate between t0 and t1: fn.call(age, life, r, i) for every particle alive at t.
static func stream(t: float, t0: float, t1: float, rate: float, seed: Variant, life: Variant, fn: Callable) -> void:
	var na := fn.get_argument_count()
	var n := floori((minf(t, t1) - t0) * rate)
	var i := 0
	while i <= n:
		var born := t0 + i / rate
		var g := rng(seed, i, 911)
		var L: float = life.call(g) if life is Callable else life
		var age := t - born
		if age >= 0.0 and age < L:
			call4(fn, na, age, L, rng(seed, i), i)
		i += 1

# -------------------------------------------------------------------------------------------------- shapes.js

## A jagged lightning path by midpoint displacement. opts: { jag = 0.22, depth = 5 }. Returns [[x, y], ...].
static func bolt(r: Rng, x0: float, y0: float, x1: float, y1: float, opts: Dictionary = {}) -> Array:
	var jag: float = opts.get("jag", 0.22)
	var depth := int(opts.get("depth", 5))
	var pts := [[x0, y0], [x1, y1]]
	for d in depth:
		var nxt := [pts[0]]
		for i in range(1, pts.size()):
			var ax: float = pts[i - 1][0]
			var ay: float = pts[i - 1][1]
			var bx: float = pts[i][0]
			var by: float = pts[i][1]
			var dx := bx - ax
			var dy := by - ay
			var L := Self.hypot(dx, dy)
			var off := (r.next() * 2.0 - 1.0) * jag * L
			var Ld := L if L else 1.0
			nxt.append([(ax + bx) / 2.0 + (-dy / Ld) * off, (ay + by) / 2.0 + (dx / Ld) * off])
			nxt.append(pts[i])
		pts = nxt
	return pts

## Forks off a bolt path. opts: { count = 3, len = 20, jag = 0.3, spread = 0.9 }. Returns a list of paths.
static func forks(r: Rng, path: Array, opts: Dictionary = {}) -> Array:
	var count := int(opts.get("count", 3))
	var ln: float = opts.get("len", 20.0)
	var jag: float = opts.get("jag", 0.3)
	var spread: float = opts.get("spread", 0.9)
	var out := []
	for k in count:
		var i := 1 + floori(r.next() * (path.size() - 2))
		var x: float = path[i][0]
		var y: float = path[i][1]
		var px: float = path[i - 1][0]
		var py: float = path[i - 1][1]
		var a := atan2(y - py, x - px) + (-1.0 if r.next() < 0.5 else 1.0) * spread * (0.4 + 0.6 * r.next())
		var l := ln * (0.4 + 0.6 * r.next())
		out.append(bolt(r, x, y, x + cos(a) * l, y + sin(a) * l, {"jag": jag, "depth": 3}))
	return out

## A star: n points between radii r1 (tips) and r0 (inner corners).
static func star(cx: float, cy: float, r0: float, r1: float, n: float = 5, rot: float = -PI / 2.0) -> Array:
	var pts := []
	for i in int(n) * 2:
		var a := rot + (i * PI) / n
		var r := r0 if i % 2 else r1
		pts.append([cx + cos(a) * r, cy + sin(a) * r])
	return pts

## A regular polygon with n sides.
static func ngon(cx: float, cy: float, r: float, n: float = 6, rot: float = 0.0) -> Array:
	var pts := []
	for i in int(n):
		pts.append([cx + cos(rot + (i * TAU) / n) * r, cy + sin(rot + (i * TAU) / n) * r])
	return pts

## Positions of pos.call(t - i * dt) for i = 0..n-1: a moving thing's trail, newest first.
static func trail(pos: Callable, t: float, n: float, dt: float) -> Array:
	var out := []
	for i in int(n):
		out.append(pos.call(maxf(0.0, t - i * dt)))
	return out

# --------------------------------------------------------------------------------------- sim.js (drawing helpers)
# port-of: src/core/sim.js@68f1a7097a6cf263b03d61a5144cfdb3938e4850 (sparkle, flare, band, crystal)

const GRAVITY := 950.0
## Particle kinds, flags and debris kinds: Px.P.SPARK, Px.PF.SMOKES, Px.B.SHARD.
const P := Sim.P
const PF := Sim.PF
const B := Sim.B
const FIRE_RAMP := Sim.FIRE_RAMP
const SMOKE_RAMP := Sim.SMOKE_RAMP

const CROSS := [[1, 0], [-1, 0], [0, 1], [0, -1]]
const DIAG := [[1, 1], [1, -1], [-1, 1], [-1, -1]]

## A star glint: arms of length arm in color c with tips in tip (defaults to c), a white heart, light.
static func sparkle(p: Painter, x: float, y: float, arm: float, c: int, tip: Variant = null, k: float = 0.6) -> void:
	var tp: int = c if tip == null else tip
	var n := roundi(arm)
	if n < 1:
		return
	var X := floorf(x)
	var Y := floorf(y)
	for d in range(1, n + 1):
		var cc := tp if d > n * 0.6 else c
		for o in CROSS:
			p.px(X + o[0] * d, Y + o[1] * d, cc)
	if n >= 3:
		for o in DIAG:
			p.px(X + o[0], Y + o[1], c)
	if n >= 6:
		for o in DIAG:
			p.px(X + o[0] * 2, Y + o[1] * 2, tp)
	p.px(X, Y, WHITE)
	p.glow(x, y, 4 + n * 2, c, k)

## An 8-ray flare: long rays on the axes, shorter between, fading out along their length. ramp dark to bright.
static func flare(p: Painter, x: float, y: float, L: float, k: float, rmp: Variant) -> void:
	if L < 1.0:
		return
	var R := Self.ramp(rmp)
	var n := R.size()
	for i in 8:
		var an := (i * PI) / 4.0
		var ln := L if i % 4 == 0 else (L * 0.6 if i % 2 == 0 else L * 0.3)
		var ca := cos(an)
		var sa := sin(an)
		var d := 0.0
		while d <= ln:
			var u := d / ln
			p.dot(x + ca * d, y + sa * d, WHITE if u < 0.35 else (R[n - 2] if u < 0.7 else R[n - 3]), 1.0 if u < 0.6 else k * 1.5 * (1.0 - u) + 0.2)
			d += 0.5

## A ring on a tilted plane (sy squashes it: 0.16 lies on the floor), thickness th inward, alpha k, colored by
## depth with ramp. keep (a Callable of the angle, or null for all) picks which part to draw: far half is
## func(g): return sin(g) < 0.
static func band(p: Painter, cx: float, cy: float, r: float, sy: float, th: float, k: float, rmp: Variant, keep: Variant = null, hot: bool = false) -> void:
	if r <= 0.0 or k <= 0.0:
		return
	var R := Self.ramp(rmp)
	var n := R.size()
	var m := ceili(r * TAU * 1.2)
	var has_keep := keep is Callable
	for j in m:
		var ang := (float(j) / m) * TAU
		var ca := cos(ang)
		var sa := sin(ang)
		if has_keep and not keep.call(ang):
			continue
		var o := th
		while o >= 0.0:
			var u := o / th
			var c: int = (WHITE if hot else R[n - 1]) if u < 0.15 else (R[n - 2] if u < 0.4 else (R[n - 3] if u < 0.7 else R[n - 4]))
			p.dot(cx + ca * (r - o), cy + sa * (r - o) * sy, c, k * (1.2 if u < 0.4 else 1.15 - u))
			o -= 0.5

static func _crystal_inside(px: float, py: float, x: float, base: float, h: float, w: float, lean: float) -> bool:
	var u := (base - (py + 0.5)) / h
	return u >= 0.0 and u <= 1.0 and absf(px + 0.5 - (x + lean * u)) <= (w / 2.0) * (1.0 - u) + 0.35

## A faceted crystal spike standing on (x, base), height h, base width w, leaning lean px at the tip, shaded in
## ramp (6+ steps). opts: { a (alpha), white (flash it white), glint (0..1 height of a sweeping highlight, or -1) }.
static func crystal(p: Painter, x: float, base: float, h: float, w: float, lean: float, rmp: Variant, opts: Dictionary = {}) -> void:
	if h < 1.5:
		return
	var R := Self.ramp(rmp)
	var n := R.size()
	var a: float = opts.get("a", 1.0)
	var top := base - h
	var ridge0 := x - w * 0.14
	var glint: float = opts.get("glint", -1.0)
	var white: bool = opts.get("white", false)
	var py := floorf(top) - 1.0
	var py1 := ceilf(base)
	var px0 := floorf(x - w / 2.0 - absf(lean) - 2.0)
	var px1 := ceilf(x + w / 2.0 + absf(lean) + 2.0)
	while py < py1:
		var px := px0
		while px <= px1:
			if not _crystal_inside(px, py, x, base, h, w, lean):
				if _crystal_inside(px - 1.0, py, x, base, h, w, lean) or _crystal_inside(px + 1.0, py, x, base, h, w, lean) or _crystal_inside(px, py + 1.0, x, base, h, w, lean) or (_crystal_inside(px, py - 1.0, x, base, h, w, lean) and py < base - 1.0):
					p.dot(px, py, R[0], a)
				px += 1.0
				continue
			if white:
				p.dot(px, py, WHITE, a)
				px += 1.0
				continue
			var u := (base - (py + 0.5)) / h
			var rx := ridge0 + (x + lean - ridge0) * u
			var c := x + lean * u
			var hw := (w / 2.0) * (1.0 - u) + 0.35
			var fx := px + 0.5
			var col: int
			if u > 0.9:
				col = WHITE
			elif absf(fx - rx) < 0.55:
				col = R[maxi(0, n - 1 - 1)]
			elif fx < rx:
				if fx - (c - hw) < 1.0:
					col = R[maxi(0, n - 1 - 1)]
				elif (fx - (c - hw)) / maxf(1.0, rx - (c - hw)) > 0.55:
					col = R[maxi(0, n - 1 - 2)]
				else:
					col = R[maxi(0, n - 1 - 3)]
			elif c + hw - fx < 1.2:
				col = R[maxi(0, n - 1 - mini(n - 2, 6))]
			elif (fx - rx) / maxf(1.0, c + hw - rx) > 0.5:
				col = R[maxi(0, n - 1 - 5)]
			else:
				col = R[maxi(0, n - 1 - 4)]
			if glint >= 0.0 and fx <= rx + 0.6:
				var g := absf(u - glint)
				if g < 0.05:
					col = WHITE
				elif g < 0.1:
					col = R[maxi(0, n - 1 - 1)]
			p.dot(px, py, col, a)
			px += 1.0
		py += 1.0

# ------------------------------------------------------------------------------------------ JS idiom helpers

## `{ ...a, ...b }` for plain objects (poses, options): a shallow copy of a with b laid over it.
static func merge(a: Dictionary, b: Dictionary = {}) -> Dictionary:
	var o := a.duplicate()
	o.merge(b, true)
	return o

## `Array.from({ length: n }, (_, i) => fn(i))`.
static func arr(n: float, fn: Callable) -> Array:
	var out := []
	var i := 0
	while i < n:
		out.append(fn.call(i))
		i += 1
	return out

## `list.sort(cmp)` exactly as V8 does it (TimSort: same comparator calls in the same order, so even a random
## comparator shuffles the same way and draws the same numbers). Stable, in place; returns list. Never sort_custom.
static func sort(list: Array, cmp: Callable) -> Array:
	return Sorter.sort(list, cmp)


# ------------------------------------------------------------------------------------- the rest of the core API

static func createFrame(w: int, h: int, ox: int = 0, oy: int = 0) -> Frame:
	return Frame.new(w, h, ox, oy)

static func clearFrame(f: Frame) -> Frame:
	return f.clear()

static func createFx(mod: Script, o: Dictionary = {}) -> Fx.Instance:
	return Fx.createFx(mod, o)

static func painterFor(frame: Frame) -> Painter:
	return Fx.painterFor(frame)

static func composite(f: Frame, out: PackedByteArray, bg: Variant = null, lightK: float = 1.0) -> PackedByteArray:
	return Fx.composite(f, out, bg, lightK)

static func resolveOptions(meta: Dictionary, o: Dictionary = {}) -> Dictionary:
	return Fx.resolveOptions(meta, o)

static func textWidth(s: String, font: String = "mini") -> int:
	return PixelFont.textWidth(s, font)

static func fonts() -> Dictionary:
	return PixelFont.FONTS

static func stockActor(k: int = 1) -> Dictionary:
	return Actor.stockActor(k)

static func drawActor(p: Painter, actor: Variant = null, a: float = 1.0) -> void:
	Actor.drawActor(p, actor, a)

const READY := Poses.READY

static func chain(cues: Array) -> Chain.Factory:
	return Chain.chain(cues)

static func shiftKeys(keys: Array, dt: float, over: Dictionary = {}) -> Array:
	return Chain.shiftKeys(keys, dt, over)

static func shiftHits(hits: Array, dt: float) -> Array:
	return Chain.shiftHits(hits, dt)
