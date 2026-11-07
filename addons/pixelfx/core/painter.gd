# The painter draws into a frame's two buffers: `color` (opaque pixels, faded with ordered dither, never
# blended) and `light` (additive glow, composited on top). Effects draw in local coordinates around their
# origin; the painter places, mirrors and rotates them, so an effect never needs to know where it is.
#
# Member names are the JS ones (C, L, tx, ty, fx, cs, sn, ox, oy, put, add, blendPx, each ...): some effects use
# them directly. Every shape goes through put/add/blendPx, which subclasses may override (clipping painters).
# Callbacks: wherever JS takes a color or alpha that may be a function, pass a Callable taking the same arguments
# (a lambda may declare fewer: only as many as it declares are passed).
# port-of: src/core/painter.js@4f397dbf558e29ad04fcba9e45488b4ee588bb39
extends RefCounted

const Px := preload("px.gd")
const PixelFont := preload("font.gd")
const Frame := preload("frame.gd")
const SELF := preload("painter.gd")

## 4x4 ordered (Bayer) thresholds: a pixel at alpha a is drawn when a is above its cell's threshold.
const BAYER: Array[float] = [0.03125, 0.53125, 0.15625, 0.65625, 0.78125, 0.28125, 0.90625, 0.40625, 0.21875, 0.71875, 0.09375, 0.59375, 0.96875, 0.46875, 0.84375, 0.34375]


## What a shade() callback writes: c (color), a (alpha), l (light color, defaults to c), k (light amount).
class Out:
	var c: Variant = 0
	var a: Variant = 1.0
	var l: Variant = 0
	var k: Variant = 0.0


var _frame: WeakRef
## The frame drawn into (held weakly: a frame keeps its painter, not the other way round).
var frame: Frame:
	get: return _frame.get_ref() if _frame else null
var w: int
var h: int
var ox: int
var oy: int
var C: PackedInt32Array
var L: PackedInt32Array
var tx := 0.0
var ty := 0.0
var fx := 1.0
var cs := 1.0
var sn := 0.0
var fade := 1.0
var lightK := 1.0
var layer := "front"
var OUT := Out.new()
## A plain painter (not a subclass that overrides put/add/blendPx): its shapes write the buffers directly.
var _plain := true


func _init(f: Frame) -> void:
	_plain = get_script() == SELF
	_frame = weakref(f)
	_read(f)
	reset()


func _read(f: Frame) -> void:
	w = f.w
	h = f.h
	ox = f.ox
	oy = f.oy
	C = f.color
	L = f.light


## Re-read the frame and clear placement, fade and light strength.
func reset():
	var f := frame
	if f != null:
		_read(f)
	tx = 0.0
	ty = 0.0
	fx = 1.0
	cs = 1.0
	sn = 0.0
	fade = 1.0
	lightK = 1.0
	layer = "front"
	return self


## Put the effect's origin at (x, y) in frame space, mirrored if flip, rotated by angle (radians).
func place(x: float, y: float, flip: bool = false, angle: float = 0.0):
	tx = x
	ty = y
	fx = -1.0 if flip else 1.0
	cs = cos(angle)
	sn = sin(angle)
	return self


# ---- transforms: local (effect) space <-> screen (frame) space
func toX(x: float, y: float) -> float:
	return tx + x * fx * cs - y * sn

func toY(x: float, y: float) -> float:
	return ty + x * fx * sn + y * cs

func fromX(sx: float, sy: float) -> float:
	var dx := sx - tx
	var dy := sy - ty
	return (dx * cs + dy * sn) * fx

func fromY(sx: float, sy: float) -> float:
	var dx := sx - tx
	var dy := sy - ty
	return -dx * sn + dy * cs

## The screen pixel of the local pixel cell holding (x, y): mirrors and rotations land on whole cells.
func cellX(x: float, y: float) -> int:
	return floori(toX(floorf(x) + 0.5, floorf(y) + 0.5))

func cellY(x: float, y: float) -> int:
	return floori(toY(floorf(x) + 0.5, floorf(y) + 0.5))


# ---- raw writes, screen space, whole pixels. Color 0 means "nothing": it never erases what's there.
func put(sx: int, sy: int, c: Variant, a: float = 1.0) -> void:
	if not c:
		return
	a *= fade
	if a < 1.0 and a <= BAYER[((sy & 3) << 2) | (sx & 3)]:
		return
	var x := sx - ox
	var y := sy - oy
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	C[y * w + x] = c


func add(sx: int, sy: int, c: int, k: float = 1.0) -> void:
	k *= fade * lightK
	if k <= 0.004:
		return
	var x := sx - ox
	var y := sy - oy
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	var i := y * w + x
	var d := L[i]
	var r := int(minf(255.0, (d & 255) + (c & 255) * k))
	var g := int(minf(255.0, ((d >> 8) & 255) + ((c >> 8) & 255) * k))
	var b := int(minf(255.0, ((d >> 16) & 255) + ((c >> 16) & 255) * k))
	L[i] = -16777216 | (b << 16) | (g << 8) | r


# add() for a plain painter: the same arithmetic, without the virtual call.
func _addFast(sx: int, sy: int, c: int, k: float) -> void:
	k *= fade * lightK
	if k <= 0.004:
		return
	var x := sx - ox
	var y := sy - oy
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	var i := y * w + x
	var d := L[i]
	L[i] = -16777216 | (int(minf(255.0, ((d >> 16) & 255) + ((c >> 16) & 255) * k)) << 16) | (int(minf(255.0, ((d >> 8) & 255) + ((c >> 8) & 255) * k)) << 8) | int(minf(255.0, (d & 255) + (c & 255) * k))


## Blend a color over what's there at alpha a (0..1), keeping the result's own alpha: soft smoke, vapour, mist.
func blendPx(sx: int, sy: int, c: Variant, a: float) -> void:
	a *= fade
	if not c or a <= 0.004:
		return
	var x := sx - ox
	var y := sy - oy
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	var i := y * w + x
	var d := C[i]
	var cc: int = c
	var da := ((d >> 24) & 255) / 255.0
	var oa := a + da * (1.0 - a)
	var k := a / oa
	var r := int((cc & 255) * k + (d & 255) * (1.0 - k)) & 255
	var g := int(((cc >> 8) & 255) * k + ((d >> 8) & 255) * (1.0 - k)) & 255
	var b := int(((cc >> 16) & 255) * k + ((d >> 16) & 255) * (1.0 - k)) & 255
	C[i] = ((int(oa * 255.0) & 255) << 24) | (b << 16) | (g << 8) | r


## Translucent pixel at a local point.
func blend(x: float, y: float, c: Variant, a: float) -> void:
	blendPx(cellX(x, y), cellY(x, y), c, a)


## A translucent disc: puffs of smoke, vapour, dust. c and a may be Callables of (d: 0 center..1 rim, angle).
func disc(cx: float, cy: float, r: float, c: Variant, a: Variant) -> void:
	var cf := c is Callable
	var af := a is Callable
	var cn: int = c.get_argument_count() if cf else 0
	var an: int = a.get_argument_count() if af else 0
	if r < 0.5:
		blend(cx, cy, _v2(c, cn, 0.0, 0.0) if cf else c, _v2(a, an, 0.0, 0.0) if af else a)
		return
	var bb := _box(cx - r, cy - r, cx + r, cy + r)
	if bb.is_empty():
		return
	var rr := r * r
	for sy in range(bb[2], bb[3] + 1):
		for sx in range(bb[0], bb[1] + 1):
			var pcx := sx + 0.5
			var pcy := sy + 0.5
			var x := fromX(pcx, pcy)
			var y := fromY(pcx, pcy)
			var dx := x - cx
			var dy := y - cy
			var d2 := dx * dx + dy * dy
			if d2 > rr:
				continue
			var d := sqrt(d2) / r
			var ang := atan2(dy, dx)
			if not _plain:
				blendPx(sx, sy, _v2(c, cn, d, ang) if cf else c, _v2(a, an, d, ang) if af else a)
				continue
			var cc: Variant = _v2(c, cn, d, ang) if cf else c
			var ba: float = (_v2(a, an, d, ang) if af else a) * fade
			if not cc or ba <= 0.004:
				continue
			var i := (sy - oy) * w + sx - ox
			var q := C[i]
			var ci: int = cc
			var da := ((q >> 24) & 255) / 255.0
			var oa := ba + da * (1.0 - ba)
			var k := ba / oa
			var cr_ := int((ci & 255) * k + (q & 255) * (1.0 - k)) & 255
			var cg_ := int(((ci >> 8) & 255) * k + ((q >> 8) & 255) * (1.0 - k)) & 255
			var cb_ := int(((ci >> 16) & 255) * k + ((q >> 16) & 255) * (1.0 - k)) & 255
			C[i] = ((int(oa * 255.0) & 255) << 24) | (cb_ << 16) | (cg_ << 8) | cr_


## Read back the color under a local point (0 if empty), unsigned like a JS Uint32Array read. (JS: p.get)
func getc(x: float, y: float) -> int:
	var sx := cellX(x, y) - ox
	var sy := cellY(x, y) - oy
	return 0 if (sx < 0 or sy < 0 or sx >= w or sy >= h) else (C[sy * w + sx] & 0xFFFFFFFF)


# ---- pixels
## One opaque pixel.
func px(x: float, y: float, c: Variant) -> void:
	if not _plain:
		put(cellX(x, y), cellY(x, y), c, 1.0)
		return
	if not c:
		return
	var cx := floorf(x) + 0.5
	var cy := floorf(y) + 0.5
	var sx := floori(tx + cx * fx * cs - cy * sn)
	var sy := floori(ty + cx * fx * sn + cy * cs)
	var a := 1.0 * fade
	if a < 1.0 and a <= BAYER[((sy & 3) << 2) | (sx & 3)]:
		return
	var X := sx - ox
	var Y := sy - oy
	if X < 0 or Y < 0 or X >= w or Y >= h:
		return
	C[Y * w + X] = c

## One pixel at alpha a (0..1), faded by ordered dither.
func dot(x: float, y: float, c: Variant, a: float = 1.0) -> void:
	if not (a > 0.0):
		return
	if not _plain:
		put(cellX(x, y), cellY(x, y), c, a)
		return
	if not c:
		return
	var cx := floorf(x) + 0.5
	var cy := floorf(y) + 0.5
	var sx := floori(tx + cx * fx * cs - cy * sn)
	var sy := floori(ty + cx * fx * sn + cy * cs)
	a *= fade
	if a < 1.0 and a <= BAYER[((sy & 3) << 2) | (sx & 3)]:
		return
	var X := sx - ox
	var Y := sy - oy
	if X < 0 or Y < 0 or X >= w or Y >= h:
		return
	C[Y * w + X] = c

## Add light to one pixel.
func light(x: float, y: float, c: int, k: float = 1.0) -> void:
	add(cellX(x, y), cellY(x, y), c, k)


## The screen box [sx0, sx1, sy0, sy1] of pixels whose centers fall in the local box (clipped to the frame).
## Empty when the box is empty or not finite.
func _box(x0: float, y0: float, x1: float, y1: float) -> Array:
	var ax := INF
	var bx := -INF
	var ay := INF
	var by := -INF
	for k in 4:
		var x := x1 if k & 1 else x0
		var y := y1 if k & 2 else y0
		var sx := toX(x, y)
		var sy := toY(x, y)
		if sx < ax: ax = sx
		if sx > bx: bx = sx
		if sy < ay: ay = sy
		if sy > by: by = sy
	var fx0 := maxf(floorf(ax), ox)
	var fx1 := minf(ceilf(bx), ox + w - 1)
	var fy0 := maxf(floorf(ay), oy)
	var fy1 := minf(ceilf(by), oy + h - 1)
	if not (fx0 <= fx1 and fy0 <= fy1) or is_inf(fx0) or is_inf(fy0) or is_inf(fx1) or is_inf(fy1):
		return []
	return [int(fx0), int(fx1), int(fy0), int(fy1)]


## Visit every screen pixel whose center falls in the local box [x0, x1] x [y0, y1], with that center in local
## space: fn.call(lx, ly, sx, sy). The basis of every filled shape, so shapes mirror and rotate exactly.
func each(x0: float, y0: float, x1: float, y1: float, fn: Callable) -> void:
	var bb := _box(x0, y0, x1, y1)
	if bb.is_empty():
		return
	for sy in range(bb[2], bb[3] + 1):
		for sx in range(bb[0], bb[1] + 1):
			var cx := sx + 0.5
			var cy := sy + 0.5
			fn.call(fromX(cx, cy), fromY(cx, cy), sx, sy)


## A pixel shader over a local box. fn.call(x, y, out) returns a color, or sets out.c (color), out.a (alpha),
## out.l (light color, defaults to out.c) and out.k (light amount). Return nothing to leave the pixel alone.
func shade(x0: float, y0: float, x1: float, y1: float, fn: Callable) -> void:
	var bb := _box(x0, y0, x1, y1)
	if bb.is_empty():
		return
	var o := OUT
	var n := fn.get_argument_count()
	for sy in range(bb[2], bb[3] + 1):
		for sx in range(bb[0], bb[1] + 1):
			var pcx := sx + 0.5
			var pcy := sy + 0.5
			var lx := fromX(pcx, pcy)
			var ly := fromY(pcx, pcy)
			o.c = 0
			o.a = 1.0
			o.l = 0
			o.k = 0.0
			var ret: Variant = fn.call(lx, ly, o) if n >= 3 else fn.call(lx, ly)
			var c: Variant = ret if ret else o.c
			if not _plain:
				if c:
					put(sx, sy, c, o.a)
				if o.k > 0.0:
					add(sx, sy, o.l if o.l else c, o.k)
				continue
			if c:
				var fa: float = o.a * fade
				if not (fa < 1.0 and fa <= BAYER[((sy & 3) << 2) | (sx & 3)]):
					C[(sy - oy) * w + sx - ox] = c
			if o.k > 0.0:
				var kk: float = o.k * (fade * lightK)
				if kk > 0.004:
					var lc: int = o.l if o.l else c
					var i := (sy - oy) * w + sx - ox
					var q := L[i]
					L[i] = -16777216 | (int(minf(255.0, ((q >> 16) & 255) + ((lc >> 16) & 255) * kk)) << 16) | (int(minf(255.0, ((q >> 8) & 255) + ((lc >> 8) & 255) * kk)) << 8) | int(minf(255.0, (q & 255) + (lc & 255) * kk))


# Calls a color/alpha Callable with as many of (x, y) as it takes.
static func _v1(f: Callable, n: int, x: Variant) -> Variant:
	return f.call(x) if n >= 1 else f.call()

static func _v2(f: Callable, n: int, x: Variant, y: Variant) -> Variant:
	return f.call(x, y) if n >= 2 else (f.call(x) if n == 1 else f.call())


# ---- shapes. Colors (c) and alphas (a) can be values or Callables of the shape's own coordinates.

## 1 px line. c and a may be Callables of u (0 at the start, 1 at the end).
func line(x0: float, y0: float, x1: float, y1: float, c: Variant, a: Variant = 1.0) -> void:
	var sx := cellX(x0, y0)
	var sy := cellY(x0, y0)
	var ex := cellX(x1, y1)
	var ey := cellY(x1, y1)
	var dx := absi(ex - sx)
	var dy := -absi(ey - sy)
	var stepx := 1 if sx < ex else -1
	var stepy := 1 if sy < ey else -1
	var n := maxi(dx, -dy)
	if n == 0:
		n = 1
	var fc := c is Callable
	var fa := a is Callable
	var cn: int = c.get_argument_count() if fc else 0
	var an: int = a.get_argument_count() if fa else 0
	var err := dx + dy
	var i := 0
	while true:
		var u := i / float(n)
		i += 1
		if _plain:
			var cc: Variant = _v1(c, cn, u) if fc else c
			if cc:
				var aa: float = (_v1(a, an, u) if fa else a) * fade
				var X := sx - ox
				var Y := sy - oy
				if not (aa < 1.0 and aa <= BAYER[((sy & 3) << 2) | (sx & 3)]) and X >= 0 and Y >= 0 and X < w and Y < h:
					C[Y * w + X] = cc
		else:
			put(sx, sy, _v1(c, cn, u) if fc else c, _v1(a, an, u) if fa else a)
		if sx == ex and sy == ey:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			sx += stepx
		if e2 <= dx:
			err += dx
			sy += stepy


## Lines through a list of points [[x, y], ...].
func polyline(pts: Array, c: Variant, a: Variant = 1.0) -> void:
	for i in range(1, pts.size()):
		line(pts[i - 1][0], pts[i - 1][1], pts[i][0], pts[i][1], c, a)


## Thick segment with round ends. c and a may be Callables of (u along, v across: 0 center, 1 edge).
func beam(x0: float, y0: float, x1: float, y1: float, width: float, c: Variant, a: Variant = 1.0) -> void:
	var r := width / 2.0
	var dx := x1 - x0
	var dy := y1 - y0
	var L2 := dx * dx + dy * dy
	if not L2:
		L2 = 1e-9
	var bb := _box(minf(x0, x1) - r, minf(y0, y1) - r, maxf(x0, x1) + r, maxf(y0, y1) + r)
	if bb.is_empty():
		return
	var cf := c is Callable
	var af := a is Callable
	var cn: int = c.get_argument_count() if cf else 0
	var an: int = a.get_argument_count() if af else 0
	var rr := r * r
	for sy in range(bb[2], bb[3] + 1):
		for sx in range(bb[0], bb[1] + 1):
			var pcx := sx + 0.5
			var pcy := sy + 0.5
			var x := fromX(pcx, pcy)
			var y := fromY(pcx, pcy)
			var u := Px.clamp(((x - x0) * dx + (y - y0) * dy) / L2)
			var qx := x0 + dx * u - x
			var qy := y0 + dy * u - y
			var d2 := qx * qx + qy * qy
			if d2 > rr:
				continue
			var v := sqrt(d2) / r
			var cc: Variant = _v2(c, cn, u, v) if cf else c
			var aa: Variant = _v2(a, an, u, v) if af else a
			if cc:
				if _plain:
					var fa: float = aa * fade
					if not (fa < 1.0 and fa <= BAYER[((sy & 3) << 2) | (sx & 3)]):
						C[(sy - oy) * w + sx - ox] = cc
				else:
					put(sx, sy, cc, aa)


## Filled disc. c and a may be Callables of (d: 0 center to 1 rim, angle).
func circle(cx: float, cy: float, r: float, c: Variant, a: Variant = 1.0) -> void:
	var cf := c is Callable
	var af := a is Callable
	var cn: int = c.get_argument_count() if cf else 0
	var an: int = a.get_argument_count() if af else 0
	if r < 0.6:
		dot(cx, cy, _v2(c, cn, 0.0, 0.0) if cf else c, _v2(a, an, 0.0, 0.0) if af else a)
		return
	var bb := _box(cx - r, cy - r, cx + r, cy + r)
	if bb.is_empty():
		return
	var rr := r * r
	var need_ang := (cf and cn >= 2) or (af and an >= 2)
	for sy in range(bb[2], bb[3] + 1):
		for sx in range(bb[0], bb[1] + 1):
			var pcx := sx + 0.5
			var pcy := sy + 0.5
			var x := fromX(pcx, pcy)
			var y := fromY(pcx, pcy)
			var dx := x - cx
			var dy := y - cy
			var d2 := dx * dx + dy * dy
			if d2 > rr:
				continue
			var cc: Variant = c
			var aa: Variant = a
			if cf or af:
				var d := sqrt(d2) / r
				var ang := atan2(dy, dx) if need_ang else 0.0
				if cf:
					cc = _v2(c, cn, d, ang)
				if af:
					aa = _v2(a, an, d, ang)
			if cc:
				if _plain:
					var fa: float = aa * fade
					if not (fa < 1.0 and fa <= BAYER[((sy & 3) << 2) | (sx & 3)]):
						C[(sy - oy) * w + sx - ox] = cc
				else:
					put(sx, sy, cc, aa)


## Ellipse. c and a may be Callables of (d: 0 center to 1 rim, angle).
func ellipse(cx: float, cy: float, rx: float, ry: float, c: Variant, a: Variant = 1.0) -> void:
	if rx <= 0.0 or ry <= 0.0:
		return
	var bb := _box(cx - rx, cy - ry, cx + rx, cy + ry)
	if bb.is_empty():
		return
	var cf := c is Callable
	var af := a is Callable
	var cn: int = c.get_argument_count() if cf else 0
	var an: int = a.get_argument_count() if af else 0
	var need_ang := (cf and cn >= 2) or (af and an >= 2)
	for sy in range(bb[2], bb[3] + 1):
		for sx in range(bb[0], bb[1] + 1):
			var pcx := sx + 0.5
			var pcy := sy + 0.5
			var x := fromX(pcx, pcy)
			var y := fromY(pcx, pcy)
			var dx := (x - cx) / rx
			var dy := (y - cy) / ry
			var d2 := dx * dx + dy * dy
			if d2 > 1.0:
				continue
			var cc: Variant = c
			var aa: Variant = a
			if cf or af:
				var d := sqrt(d2)
				var ang := atan2(dy, dx) if need_ang else 0.0
				if cf:
					cc = _v2(c, cn, d, ang)
				if af:
					aa = _v2(a, an, d, ang)
			if cc:
				if _plain:
					var fa: float = aa * fade
					if not (fa < 1.0 and fa <= BAYER[((sy & 3) << 2) | (sx & 3)]):
						C[(sy - oy) * w + sx - ox] = cc
				else:
					put(sx, sy, cc, aa)


## Ring from radius r - w to r. c and a may be Callables of (v: 0 inner to 1 outer, angle).
func ring(cx: float, cy: float, r: float, w_: float, c: Variant, a: Variant = 1.0) -> void:
	var r0 := maxf(0.0, r - w_)
	var bb := _box(cx - r, cy - r, cx + r, cy + r)
	if bb.is_empty():
		return
	var cf := c is Callable
	var af := a is Callable
	var cn: int = c.get_argument_count() if cf else 0
	var an: int = a.get_argument_count() if af else 0
	var need_ang := (cf and cn >= 2) or (af and an >= 2)
	var rr := r * r
	var rr0 := r0 * r0
	var span := r - r0
	if not span:
		span = 1.0
	for sy in range(bb[2], bb[3] + 1):
		for sx in range(bb[0], bb[1] + 1):
			var pcx := sx + 0.5
			var pcy := sy + 0.5
			var x := fromX(pcx, pcy)
			var y := fromY(pcx, pcy)
			var dx := x - cx
			var dy := y - cy
			var d2 := dx * dx + dy * dy
			if d2 > rr or d2 < rr0:
				continue
			var cc: Variant = c
			var aa: Variant = a
			if cf or af:
				var v := (sqrt(d2) - r0) / span if w_ > 0.0 else 1.0
				var ang := atan2(dy, dx) if need_ang else 0.0
				if cf:
					cc = _v2(c, cn, v, ang)
				if af:
					aa = _v2(a, an, v, ang)
			if cc:
				if _plain:
					var fa: float = aa * fade
					if not (fa < 1.0 and fa <= BAYER[((sy & 3) << 2) | (sx & 3)]):
						C[(sy - oy) * w + sx - ox] = cc
				else:
					put(sx, sy, cc, aa)


## Band of a ring from angle a0 to a1 (radians, a1 > a0), radius r - w to r: the slash and smear shape.
## c and a may be Callables of (u: 0 at a0 to 1 at a1, v: 0 inner to 1 outer). w may be a Callable of u.
func arc(cx: float, cy: float, r: float, w_: Variant, a0: float, a1: float, c: Variant, a: Variant = 1.0) -> void:
	var span := a1 - a0
	var wf := w_ is Callable
	var bb := _box(cx - r, cy - r, cx + r, cy + r)
	if bb.is_empty():
		return
	var cf := c is Callable
	var af := a is Callable
	var cn: int = c.get_argument_count() if cf else 0
	var an: int = a.get_argument_count() if af else 0
	for sy in range(bb[2], bb[3] + 1):
		for sx in range(bb[0], bb[1] + 1):
			var pcx := sx + 0.5
			var pcy := sy + 0.5
			var x := fromX(pcx, pcy)
			var y := fromY(pcx, pcy)
			var dx := x - cx
			var dy := y - cy
			var d := sqrt(dx * dx + dy * dy)
			if d > r:
				continue
			var ang := atan2(dy, dx) - a0
			ang -= floorf(ang / (PI * 2.0)) * PI * 2.0
			if ang > span:
				continue
			var u := ang / span
			var ww: float = w_.call(u) if wf else w_
			if ww <= 0.0 or d < r - ww:
				continue
			var v := (d - (r - ww)) / ww
			var cc: Variant = _v2(c, cn, u, v) if cf else c
			var aa: Variant = _v2(a, an, u, v) if af else a
			if cc:
				if _plain:
					var fa: float = aa * fade
					if not (fa < 1.0 and fa <= BAYER[((sy & 3) << 2) | (sx & 3)]):
						C[(sy - oy) * w + sx - ox] = cc
				else:
					put(sx, sy, cc, aa)


## Filled rectangle.
func rect(x: float, y: float, w_: float, h_: float, c: Variant, a: Variant = 1.0) -> void:
	if sn == 0.0:
		var X0 := int(Px.round(x))
		var Y0 := int(Px.round(y))
		var X1 := int(Px.round(x + w_))
		var Y1 := int(Px.round(y + h_))
		for yy in range(Y0, Y1):
			for xx in range(X0, X1):
				put(cellX(xx, yy), cellY(xx, yy), c, a)
		return
	var bb := _box(x, y, x + w_, y + h_)
	if bb.is_empty():
		return
	for sy in range(bb[2], bb[3] + 1):
		for sx in range(bb[0], bb[1] + 1):
			var pcx := sx + 0.5
			var pcy := sy + 0.5
			var lx := fromX(pcx, pcy)
			var ly := fromY(pcx, pcy)
			if lx < x or ly < y or lx >= x + w_ or ly >= y + h_:
				continue
			if c:
				put(sx, sy, c, a)


## Filled polygon from points [[x, y], ...] (even-odd rule). c and a may be Callables of (x, y).
func poly(pts: Array, c: Variant, a: Variant = 1.0) -> void:
	var x0 := INF
	var y0 := INF
	var x1 := -INF
	var y1 := -INF
	for p in pts:
		var px_: float = p[0]
		var py_: float = p[1]
		if px_ < x0: x0 = px_
		if px_ > x1: x1 = px_
		if py_ < y0: y0 = py_
		if py_ > y1: y1 = py_
	var n := pts.size()
	var bb := _box(x0, y0, x1, y1)
	if bb.is_empty():
		return
	var cf := c is Callable
	var af := a is Callable
	var cn: int = c.get_argument_count() if cf else 0
	var an: int = a.get_argument_count() if af else 0
	for sy in range(bb[2], bb[3] + 1):
		for sx in range(bb[0], bb[1] + 1):
			var pcx := sx + 0.5
			var pcy := sy + 0.5
			var x := fromX(pcx, pcy)
			var y := fromY(pcx, pcy)
			var inside := false
			var j := n - 1
			for i in n:
				var xi: float = pts[i][0]
				var yi: float = pts[i][1]
				var xj: float = pts[j][0]
				var yj: float = pts[j][1]
				if (yi > y) != (yj > y) and x < ((xj - xi) * (y - yi)) / (yj - yi) + xi:
					inside = not inside
				j = i
			if not inside:
				continue
			var cc: Variant = _v2(c, cn, x, y) if cf else c
			var aa: Variant = _v2(a, an, x, y) if af else a
			if cc:
				if _plain:
					var fa: float = aa * fade
					if not (fa < 1.0 and fa <= BAYER[((sy & 3) << 2) | (sx & 3)]):
						C[(sy - oy) * w + sx - ox] = cc
				else:
					put(sx, sy, cc, aa)


func tri(x0: float, y0: float, x1: float, y1: float, x2: float, y2: float, c: Variant, a: Variant = 1.0) -> void:
	poly([[x0, y0], [x1, y1], [x2, y2]], c, a)


# ---- light
## Radial glow into the light buffer: k at the center, falling to 0 at radius r.
func glow(x: float, y: float, r: float, c: int, k: float = 0.5) -> void:
	if r < 1.0 or k <= 0.004:
		return
	var cx := toX(x, y)
	var cy := toY(x, y)
	var x0 := floorf(cx - r)
	var x1 := ceilf(cx + r)
	var y0 := floorf(cy - r)
	var y1 := ceilf(cy + r)
	if is_inf(x0) or is_inf(y0) or is_nan(x0) or is_nan(y0):
		return
	if not _plain:
		for sy in range(int(y0), int(y1) + 1):
			var dy := (sy + 0.5 - cy) / r
			for sx in range(int(x0), int(x1) + 1):
				var dx := (sx + 0.5 - cx) / r
				var d := dx * dx + dy * dy
				if d >= 1.0:
					continue
				var f := 1.0 - sqrt(d)
				add(sx, sy, c, f * f * k)
		return
	# the same, with add() written in and the loops cut to the frame (add() drops what's outside it)
	var fl := fade * lightK
	var cr := c & 255
	var cg := (c >> 8) & 255
	var cb := (c >> 16) & 255
	for sy in range(maxi(int(y0), oy), mini(int(y1), oy + h - 1) + 1):
		var dy := (sy + 0.5 - cy) / r
		var row := (sy - oy) * w - ox
		for sx in range(maxi(int(x0), ox), mini(int(x1), ox + w - 1) + 1):
			var dx := (sx + 0.5 - cx) / r
			var d := dx * dx + dy * dy
			if d >= 1.0:
				continue
			var f := 1.0 - sqrt(d)
			var kk := f * f * k * fl
			if kk <= 0.004:
				continue
			var i := row + sx
			var q := L[i]
			L[i] = -16777216 | (int(minf(255.0, ((q >> 16) & 255) + cb * kk)) << 16) | (int(minf(255.0, ((q >> 8) & 255) + cg * kk)) << 8) | int(minf(255.0, (q & 255) + cr * kk))


## Glow around a segment (a soft beam of light).
func glowLine(x0: float, y0: float, x1: float, y1: float, r: float, c: int, k: float = 0.5) -> void:
	if r < 1.0 or k <= 0.004:
		return
	var ax := toX(x0, y0)
	var ay := toY(x0, y0)
	var bx := toX(x1, y1)
	var by := toY(x1, y1)
	var dx := bx - ax
	var dy := by - ay
	var L2 := dx * dx + dy * dy
	if not L2:
		L2 = 1e-9
	var X0 := floorf(minf(ax, bx) - r)
	var X1 := ceilf(maxf(ax, bx) + r)
	var Y0 := floorf(minf(ay, by) - r)
	var Y1 := ceilf(maxf(ay, by) + r)
	if is_inf(X0) or is_inf(Y0) or is_nan(X0) or is_nan(Y0):
		return
	for sy in range(int(Y0), int(Y1) + 1):
		for sx in range(int(X0), int(X1) + 1):
			var qx := sx + 0.5
			var qy := sy + 0.5
			var u := Px.clamp(((qx - ax) * dx + (qy - ay) * dy) / L2)
			var ex := ax + dx * u - qx
			var ey := ay + dy * u - qy
			var d := sqrt(ex * ex + ey * ey) / r
			if d >= 1.0:
				continue
			var f := 1.0 - d
			if _plain:
				_addFast(sx, sy, c, f * f * k)
			else:
				add(sx, sy, c, f * f * k)


## Glow hugging a circle of radius R (a shockwave's light), falling off over width r.
func glowRing(x: float, y: float, R: float, r: float, c: int, k: float = 0.5) -> void:
	if r < 1.0 or k <= 0.004:
		return
	var cx := toX(x, y)
	var cy := toY(x, y)
	var E := R + r
	var y0 := floorf(cy - E)
	var y1 := ceilf(cy + E)
	var x0 := floorf(cx - E)
	var x1 := ceilf(cx + E)
	if is_inf(x0) or is_inf(y0) or is_nan(x0) or is_nan(y0):
		return
	for sy in range(int(y0), int(y1) + 1):
		for sx in range(int(x0), int(x1) + 1):
			var d := absf(Px.hypot(sx + 0.5 - cx, sy + 0.5 - cy) - R) / r
			if d >= 1.0:
				continue
			var f := 1.0 - d
			if _plain:
				_addFast(sx, sy, c, f * f * k)
			else:
				add(sx, sy, c, f * f * k)


# ---- sprites, text, masks
## A little sprite from strings: rows like ["..##..", ".#oo#."], pal maps characters to colors
## ({ "#": "#222034", "o": 0xff... }); "." and " " are empty. Top-left at (x, y).
## opts: { scale, a, flip (mirror left-right), flipY (upside down), tint (draw every pixel in one color) }.
func sprite(rows: Array, pal: Dictionary, x: float, y: float, opts: Dictionary = {}) -> void:
	var k: float = opts.get("scale", 1.0)
	var a: float = opts.get("a", 1.0)
	var W: int = String(rows[0]).length() if rows.size() else 0
	var has_tint := opts.has("tint") and opts.tint != null
	var flip: bool = opts.get("flip", false)
	var flipY: bool = opts.get("flipY", false)
	var cache := {}
	for r in rows.size():
		var row: String = rows[r]
		for q in row.length():
			var ch := row[q]
			if ch == "." or ch == " ":
				continue
			var c: Variant
			if has_tint:
				c = opts.tint
			else:
				c = cache.get(ch)
				if c == null:
					c = 0 if pal.get(ch) == null else Px.hex(pal[ch])
					cache[ch] = c
			if not c:
				continue
			var col := W - 1 - q if flip else q
			var rw := rows.size() - 1 - r if flipY else r
			if k == 1.0:
				dot(x + col, y + rw, c, a)
			else:
				rect(x + col * k, y + rw * k, k, k, c, a)


## Pixel text. opts: { font: "mini" (3x5) | "big" (5x7), scale, align: "left" | "center" | "right",
## outline: color, shadow: color, a }. (x, y) is the top of the text, at the left, center or right.
## c may be a Callable of (gx, gy), the font pixel.
func text(s: Variant, x: float, y: float, c: Variant, opts: Dictionary = {}) -> void:
	var font: String = opts.get("font", "mini")
	var k: float = opts.get("scale", 1.0)
	var a: float = opts.get("a", 1.0)
	var tw := PixelFont.textWidth(s, font) * k
	var align: String = opts.get("align", "left")
	var left := Px.round(x - tw / 2.0 if align == "center" else (x - tw if align == "right" else x))
	var top := Px.round(y)
	if opts.has("outline") and opts.outline != null:
		var ol: Variant = opts.outline
		PixelFont.rasterText(s, font, func(gx, gy): rect(left + gx * k - 1.0, top + gy * k - 1.0, k + 2.0, k + 2.0, ol, a))
	if opts.has("shadow") and opts.shadow != null:
		var sh: Variant = opts.shadow
		PixelFont.rasterText(s, font, func(gx, gy): rect(left + gx * k + 1.0, top + gy * k + 1.0, k, k, sh, a))
	var cf := c is Callable
	var cn: int = c.get_argument_count() if cf else 0
	PixelFont.rasterText(s, font, func(gx, gy): rect(left + gx * k, top + gy * k, k, k, _v2(c, cn, gx, gy) if cf else c, a))


## Size of text in pixels: [w, h].
func measure(s: Variant, opts: Dictionary = {}) -> Array:
	var k: float = opts.get("scale", 1.0)
	var font: String = opts.get("font", "mini")
	return [PixelFont.textWidth(s, font) * k, PixelFont.FONTS[font].h * k]


## Fill a mask ({ w, h, data }) with its top-left at (x, y). c and a may be Callables of (mx, my).
func mask(m: Dictionary, x: float, y: float, c: Variant, a: Variant = 1.0) -> void:
	var cf := c is Callable
	var af := a is Callable
	var cn: int = c.get_argument_count() if cf else 0
	var an: int = a.get_argument_count() if af else 0
	var mw: int = m.w
	var mh: int = m.h
	var data: Variant = m.data
	for my in mh:
		for mx in mw:
			if data[my * mw + mx]:
				dot(x + mx, y + my, _v2(c, cn, mx, my) if cf else c, _v2(a, an, mx, my) if af else a)


## The 1 px outline just outside a mask.
func outline(m: Dictionary, x: float, y: float, c: Variant, a: Variant = 1.0) -> void:
	var cf := c is Callable
	var af := a is Callable
	var cn: int = c.get_argument_count() if cf else 0
	var an: int = a.get_argument_count() if af else 0
	var mw: int = m.w
	var mh: int = m.h
	var data: Variant = m.data
	var at := func(mx: int, my: int) -> bool:
		return mx >= 0 and my >= 0 and mx < mw and my < mh and data[my * mw + mx]
	for my in range(-1, mh + 1):
		for mx in range(-1, mw + 1):
			if not at.call(mx, my) and (at.call(mx - 1, my) or at.call(mx + 1, my) or at.call(mx, my - 1) or at.call(mx, my + 1)):
				dot(x + mx, y + my, _v2(c, cn, mx, my) if cf else c, _v2(a, an, mx, my) if af else a)
