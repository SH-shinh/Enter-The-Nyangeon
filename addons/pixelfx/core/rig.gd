# The character who acts: a real skeleton in 3D, drawn down to pixels the way Dead Cells makes its sprites. Bones have
# fixed lengths and hang from each other, pelvis to spine to chest to shoulders, so the body can twist, bend and turn
# round, and depth decides what's in front. A pose only says where the hands and feet should be and how the body is
# carrying itself; the solver works out every joint, and the renderer shades it into a few flat tones with one ink line.
#
# Coordinates: x right, y up, z towards the viewer, in pixels, the feet at the origin. Poses are in screen terms (y
# negative is up), as effects are. A rendered pose also knows, for each of its pixels, which pixel of the standing
# character it came from (`src`), so an effect drawn on the standing body follows the body wherever it goes.
#
# Vectors are [x, y, z] Arrays and rotations 3x3 row-major Arrays of floats, as in the JS. Colors here are unsigned
# (JS `hex(v) >>> 0`). The depth and tone buffers are float32, like the JS Float32Arrays.
# port-of: src/core/rig.js@525b7145624f53722fde335503cdf271d3958ca5
extends RefCounted

const Px := preload("px.gd")
const Self := preload("rig.gd")
const Actor := preload("actor.gd")

const DEG := PI / 180.0
const W0 := 24
const H0 := 38

## The body's measurements, in pixels.
const M := {
	"pelvis": 19.7, "spine1": 2.8, "spine2": 4.6, "shoulderUp": 2.5, "shoulderOut": 5.9, "neckUp": 4.0, "headUp": 3.1,
	"hipDown": 1.1, "hipOut": 2.8, "thigh": 8.6, "shin": 8.3, "upper": 7.6, "fore": 7.4, "turn": 36.0 * DEG,
}
## Standing easy, in screen terms: hands and feet are where they should end up, y negative is up.
const STAND := {"lean": 0, "crouch": 0, "yaw": 0, "fx": -3, "fy": -15, "bx": 5, "by": -15, "ffx": -2, "ffy": -4, "fbx": 3, "fby": -4}

## Parts: each has its own number, so edges between them can be seen.
const PART := {"pelvis": 1, "waist": 2, "chest": 3, "neck": 4, "head": 5, "face": 6, "upperN": 7, "elbowN": 8, "foreN": 9, "handN": 10, "upperF": 11, "elbowF": 12, "foreF": 13, "handF": 14, "thighN": 15, "kneeN": 16, "shinN": 17, "footN": 18, "thighF": 19, "kneeF": 20, "shinF": 21, "footF": 22, "weapon": 23, "offWeapon": 24}
const FRAME_IDS := ["pelvis", "waist", "chest", "head", "neck", "upperN", "foreN", "upperF", "foreF", "thighN", "shinN", "thighF", "shinF", "footN", "footF"]

## What the near hand can hold: `two` is where the other hand goes on the handle, `across` that the handle lies across it.
const WEAPONS := {
	"sword": {"two": -4.4}, "greatsword": {"two": -4.8}, "dagger": {}, "spear": {"two": -12.0}, "hammer": {"two": -7.0},
	"scythe": {"two": -11.0}, "claw": {}, "bow": {"across": true}, "pistol": {"across": true}, "launcher": {"two": -9.0}, "handle": {},
}

# ---- vectors and turns
static func add(a: Array, b: Array) -> Array:
	return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]

static func sub(a: Array, b: Array) -> Array:
	return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]

static func mul(a: Array, s: float) -> Array:
	return [a[0] * s, a[1] * s, a[2] * s]

static func vdot(a: Array, b: Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

static func cross(a: Array, b: Array) -> Array:
	return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

static func vlen(a: Array) -> float:
	return Px.hypot(a[0], a[1], a[2])

static func unit(a: Array) -> Array:
	var l := vlen(a)
	return mul(a, 1.0 / (l if l else 1e-6))

static func rotY(t: float) -> Array:
	var c := cos(t)
	var s := sin(t)
	return [c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c]

static func rotZ(t: float) -> Array:
	var c := cos(t)
	var s := sin(t)
	return [c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0]

static func mm(A: Array, B: Array) -> Array:
	var o := []
	o.resize(9)
	for r in 3:
		for c in 3:
			o[r * 3 + c] = A[r * 3] * B[c] + A[r * 3 + 1] * B[3 + c] + A[r * 3 + 2] * B[6 + c]
	return o

static func mv(Mx: Array, v: Array) -> Array:
	return [Mx[0] * v[0] + Mx[1] * v[1] + Mx[2] * v[2], Mx[3] * v[0] + Mx[4] * v[1] + Mx[5] * v[2], Mx[6] * v[0] + Mx[7] * v[1] + Mx[8] * v[2]]

static func tv(Mx: Array, v: Array) -> Array:
	return [Mx[0] * v[0] + Mx[3] * v[1] + Mx[6] * v[2], Mx[1] * v[0] + Mx[4] * v[1] + Mx[7] * v[2], Mx[2] * v[0] + Mx[5] * v[1] + Mx[8] * v[2]]

static func clamp01(v: float) -> float:
	return maxf(0.0, minf(1.0, v))

static func _nn(v: Variant, d: Variant) -> Variant:
	return d if v == null else v


# ---- solving a pose: from where the hands and feet should be, to every joint
static func ik(a: Array, target: Array, L1: float, L2: float, pole: Array) -> Dictionary:
	var to := sub(target, a)
	var d := vlen(to)
	var reach := L1 + L2 - 0.02
	if d > reach:
		to = mul(to, reach / d)
		d = reach
	var u := unit(to)
	var along := (L1 * L1 - L2 * L2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(0.0, L1 * L1 - along * along))
	var v := sub(pole, mul(u, vdot(pole, u)))
	v = unit(cross(u, [0.0, 0.0, 1.0])) if vlen(v) < 1e-4 else unit(v)
	return {"joint": add(a, add(mul(u, along), mul(v, h))), "end": add(a, to), "u": u, "v": v}


static func frame(t: Array, R: Array) -> Dictionary:
	return {"t": t, "R": R}


## A frame along a bone: its local x runs down the bone.
static func boneFrame(a: Array, b: Array, pole: Array) -> Dictionary:
	var x := unit(sub(b, a))
	var y := sub(pole, mul(x, vdot(pole, x)))
	y = unit(cross(x, [0.0, 0.0, 1.0])) if vlen(y) < 1e-4 else unit(y)
	var z := cross(x, y)
	return frame(a, [x[0], y[0], z[0], x[1], y[1], z[1], x[2], y[2], z[2]])


static func _hipAt(pelvis: Array, Rp: Array, s: float) -> Array:
	return add(pelvis, mv(Rp, [0.0, -M.hipDown, s * M.hipOut]))


static func _pick(chest: Array, Rc: Array, s: float, target: Array) -> Array:
	var base := add(chest, mv(Rc, [0.0, M.shoulderUp, s * M.shoulderOut]))
	var to := sub(target, base)
	var d := vlen(to)
	return add(base, mul(unit(to), minf(1.8, maxf(0.0, d - 11.0) * 0.35)))


static func _pole(s: float, T: Array, shoulder: Array, hold: Variant) -> Array:
	# elbows hang down and back; overhead they go out and forward
	var up := clamp01((T[1] - shoulder[1] + 2.0) / 10.0)
	var base := [-0.55 + up * 1.1, -1.0 + up * 0.9, s * (0.45 + up * 0.5)]
	if hold == null:
		return base
	# holding something, the forearm wants to meet the handle side on: try round the circle, keep the best
	var u := unit(sub(T, shoulder))
	var best := base
	var score := INF
	for i in 16:
		var a := (i / 16.0) * PI * 2.0
		var x := unit(cross(u, [0.3, 1.0, 0.2]))
		var y := cross(u, x)
		var v := add(mul(x, cos(a)), mul(y, sin(a)))
		var A := ik(shoulder, T, M.upper, M.fore, v)
		var f := unit(sub(A.end, A.joint))
		var cost := absf(vdot(f, hold)) * 0.7 + (1.0 - vdot(unit(base), v)) * 0.55
		if cost < score:
			score = cost
			best = v
	return best


static func solve(pose: Dictionary) -> Dictionary:
	var q := Px.merge(STAND, pose)
	var lean: float = q.lean
	var W: Variant = WEAPONS.get(q.weapon) if q.get("weapon") else null
	var OW: Variant = WEAPONS.get(q.offWeapon) if q.get("offWeapon") else null
	var sa: float = _nn(q.get("sa"), 0.0)
	var wl: float = _nn(q.get("wl"), 1.0)
	var axisZ := sqrt(maxf(0.0, 1.0 - wl * wl)) * float(_nn(q.get("wz"), 1.0))
	var axis := [cos(sa) * wl, -sin(sa) * wl, axisZ]
	var side := [-sin(sa), -cos(sa), 0.0]
	var two: bool = true if (q.get("two") and W != null) else false
	var nearZ: float = _nn(q.get("fz"), 3.0 if two else 4.5)
	# how the chest is turned follows the hands: a hand driving forward brings its shoulder round; one drawn back opens him up
	var fwd: float = (q.fx - STAND.fx) / 24.0
	var farFwd: float = 0.0 if two else (q.bx - STAND.bx) / 22.0
	var turn: float = M.turn + (-44.0 * DEG * minf(1.0, fwd) if fwd >= 0.0 else 28.0 * DEG * minf(1.0, -fwd * 1.8))
	turn += (34.0 * DEG * minf(1.0, farFwd) if farFwd > 0.0 else 0.0) + float(_nn(q.get("twist"), 0.0)) * 4.0 * DEG
	if q.get("turn") != null:
		turn = q.turn
	var hipTurn: float = M.turn + (turn - M.turn) * 0.45
	var tilt := atan2(lean, 13.0)
	var Rp := mm(rotZ(-tilt * 0.25), rotY(-hipTurn))
	var Rc := mm(rotZ(-tilt), rotY(-turn))
	# feet first: the pelvis sinks if that's what it takes for both legs to reach them
	var ankleN := [float(q.ffx), -q.ffy - 1.8, float(_nn(q.get("fzz"), 2.4))]
	var ankleF := [float(q.fbx), -q.fby - 1.8, float(_nn(q.get("bzz"), -2.4))]
	var pelvis := [lean * 0.2, M.pelvis - q.crouch, 0.0]
	var maxLeg: float = (M.thigh + M.shin) * 0.995
	for sa_ in [[1.0, ankleN], [-1.0, ankleF]]:
		var h := _hipAt(pelvis, Rp, sa_[0])
		var a: Array = sa_[1]
		var dx: float = h[0] - a[0]
		var dz: float = h[2] - a[2]
		var flat := dx * dx + dz * dz
		if flat < maxLeg * maxLeg:
			var top: float = a[1] + sqrt(maxLeg * maxLeg - flat)
			if h[1] > top:
				pelvis = [pelvis[0], pelvis[1] - (h[1] - top), pelvis[2]]
	var waist := add(pelvis, [sin(tilt * 0.45) * M.spine1, cos(tilt * 0.45) * M.spine1, 0.0])
	var chest := add(waist, [sin(tilt) * M.spine2, cos(tilt) * M.spine2, 0.0])
	var neck := add(chest, mv(Rc, [0.0, M.neckUp, 0.0]))
	# the head keeps looking where he's going: it takes only part of the lean and part of the turn
	var headTurn: float = M.turn * 0.9 + (turn - M.turn) * 0.35
	var nod := tilt * 0.35 + float(_nn(q.get("hy"), 0.0)) * 7.0 * DEG
	var roll := float(_nn(q.get("hx"), 0.0)) * 7.0 * DEG
	var Rh := mm(rotZ(-nod - roll), rotY(-headTurn))
	var head := add(neck, mv(Rh, [0.15, M.headUp, 0.0]))
	# the arms: shoulders reach a little towards a far hand
	var nearT := [float(q.fx), -q.fy, nearZ]
	var farT: Array
	if two:
		farT = [q.fx + axis[0] * W.two, -q.fy + axis[1] * W.two, nearZ + axis[2] * W.two]
	else:
		farT = [float(q.bx), -q.by, float(_nn(q.get("bz"), 5.5 if q.get("armsFront") else -4.5))]
	var sN := _pick(chest, Rc, 1.0, nearT)
	var sF := _pick(chest, Rc, -1.0, farT)
	var holdN: Variant = null
	if W != null:
		holdN = side if W.get("across") else axis
	var holdF: Variant = null
	if two:
		holdF = side if W.get("across") else axis
	elif OW != null:
		var sb: float = _nn(q.get("sb"), PI)
		holdF = [cos(sb), -sin(sb), 0.0]
	var armN := ik(sN, nearT, M.upper, M.fore, _pole(1.0, nearT, sN, holdN))
	var armF := ik(sF, farT, M.upper, M.fore, _pole(-1.0, farT, sF, holdF))
	# the legs: knees forward, a little out
	var hipN := _hipAt(pelvis, Rp, 1.0)
	var hipF := _hipAt(pelvis, Rp, -1.0)
	var legN := ik(hipN, ankleN, M.thigh, M.shin, mv(Rp, [1.0, 0.0, 1.0 * 0.35]))
	var legF := ik(hipF, ankleF, M.thigh, M.shin, mv(Rp, [1.0, 0.0, -1.0 * 0.35]))
	var B := {
		"pelvis": frame(pelvis, Rp), "waist": frame(waist, mm(rotZ(-tilt * 0.6), rotY(-(turn + hipTurn) / 2.0))), "chest": frame(chest, Rc), "head": frame(head, Rh), "neck": frame(neck, Rh),
		"upperN": boneFrame(sN, armN.joint, armN.v), "foreN": boneFrame(armN.joint, armN.end, armN.v), "upperF": boneFrame(sF, armF.joint, armF.v), "foreF": boneFrame(armF.joint, armF.end, armF.v),
		"thighN": boneFrame(hipN, legN.joint, legN.v), "shinN": boneFrame(legN.joint, legN.end, legN.v), "thighF": boneFrame(hipF, legF.joint, legF.v), "shinF": boneFrame(legF.joint, legF.end, legF.v),
	}
	var fN := hipTurn * 0.6 + 1.0 * 8.0 * DEG
	var fF := hipTurn * 0.6 + -1.0 * 8.0 * DEG
	B.footN = frame(legN.end, mm(rotY(-atan2(sin(fN), cos(fN))), rotZ(-55.0 * DEG if q.get("toeF") else 0.0)))
	B.footF = frame(legF.end, mm(rotY(-atan2(sin(fF), cos(fF))), rotZ(-55.0 * DEG if q.get("toeB") else 0.0)))
	return {"B": B, "W": W, "OW": OW, "q": q, "axis": axis, "side": side, "armN": armN, "armF": armF, "legN": legN, "legF": legF, "sN": sN, "sF": sF, "hipN": hipN, "hipF": hipF, "turn": turn}


# ---- drawing: every part goes through one depth buffer
const BW := 300
const BH := 240
const OX := 150
const OY := 180
static var Zb := PackedFloat32Array()
static var Tone := PackedFloat32Array()
static var Part := PackedInt32Array()
static var Mat := PackedInt32Array()
static var Fr := PackedInt32Array()
static var LX := PackedFloat32Array()
static var LY := PackedFloat32Array()
static var Col := PackedInt64Array()
static var touched: Array = []
static var LIGHT: Array = []
static var clipBody := false
static var clipWeapon := false
static var curFrameIndex := 0
static var curDim := 0
static var onlyPart := 0
static var PAL := {}
static var INK := 0
static var SEAM := 0
static var MARK := 0
static var SHELL: Array = []
static var CORE: Array = []
static var STEEL := {}
static var REST_FRAMES: Variant = null
static var CACHE := {}


static func _setup() -> void:
	if not LIGHT.is_empty():
		return
	var n := BW * BH
	Zb.resize(n)
	Tone.resize(n)
	LX.resize(n)
	LY.resize(n)
	Part.resize(n)
	Mat.resize(n)
	Fr.resize(n)
	Col.resize(n)
	LIGHT = unit([-0.55, 0.72, 0.5])
	for k in Actor.DUMMY_PAL:
		PAL[k] = Px.hex(Actor.DUMMY_PAL[k]) & 0xFFFFFFFF
	INK = PAL.k
	SEAM = PAL.J
	MARK = PAL.m
	SHELL = [PAL.A, PAL.B, PAL.C, PAL.D]
	CORE = [PAL.E, PAL.F, PAL.G, PAL.G]
	var steel := {"hi": "#ffffff", "a": "#e8edf6", "b": "#a4afc6", "d": "#68748f", "gold": "#ffd84a", "goldD": "#b8862a", "grip": "#7a3a2a", "gripD": "#4a2018", "wood": "#8a5a32", "woodD": "#5a3820", "dark": "#3a3448", "darkD": "#262033", "olive": "#58663f", "oliveA": "#7d8c58", "oliveD": "#3a4529"}
	for k in steel:
		STEEL[k] = Px.hex(steel[k]) & 0xFFFFFFFF
	REST_FRAMES = solve({}).B


static func plot(i: int, z: float, tone: float, part: int, mat: int, wx: float, wy: float, color: int) -> void:
	if onlyPart and part != onlyPart:
		return
	if i < 0 or i >= BW * BH:
		return
	if Part[i] == 0:
		touched.append(i)
	elif z <= Zb[i]:
		return
	Zb[i] = z
	Tone[i] = tone
	Part[i] = part
	Mat[i] = mat
	Fr[i] = curFrameIndex
	LX[i] = wx
	LY[i] = wy
	Col[i] = color


static func sphere(c: Array, r: float, part: int, mat: int) -> void:
	var x0 := floorf(c[0] - r)
	var x1 := ceilf(c[0] + r)
	var y0 := floorf(c[1] - r)
	var y1 := ceilf(c[1] + r)
	var wy := y0
	while wy <= y1:
		var wx := x0
		while wx <= x1:
			var dx: float = wx - c[0]
			var dy: float = wy - c[1]
			var d2 := dx * dx + dy * dy
			if d2 > r * r or (clipBody and wy < 1.5):
				wx += 1.0
				continue
			var dz := sqrt(r * r - d2)
			var n := [dx / r, dy / r, dz / r]
			var i := int((OY - wy) * BW + (OX + wx))
			plot(i, c[2] + dz, vdot(n, LIGHT), part, mat, wx, wy, 0)
			wx += 1.0
		wy += 1.0


static func sweep(a: Array, b: Array, ra: float, rb: float, part: int, mat: int, bulge: float = 0.0) -> void:
	var n := maxi(2, ceili(vlen(sub(b, a)) / 0.4))
	for k in n + 1:
		var u := k / float(n)
		sphere(add(a, mul(sub(b, a), u)), ra + (rb - ra) * u + bulge * sin(u * PI), part, mat)


## An ellipsoid with radii r along the axes of frame R, seen along z.
static func ellipsoid(c: Array, R: Array, r: Array, part: int, mat: int) -> void:
	var big: float = maxf(r[0], maxf(r[1], r[2]))
	var x0 := floorf(c[0] - big)
	var x1 := ceilf(c[0] + big)
	var y0 := floorf(c[1] - big)
	var y1 := ceilf(c[1] + big)
	var D := [1.0 / (r[0] * r[0]), 1.0 / (r[1] * r[1]), 1.0 / (r[2] * r[2])]
	# A = R diag(D) R^T
	var A := []
	A.resize(9)
	for i in 3:
		for j in 3:
			A[i * 3 + j] = R[i * 3] * D[0] * R[j * 3] + R[i * 3 + 1] * D[1] * R[j * 3 + 1] + R[i * 3 + 2] * D[2] * R[j * 3 + 2]
	var wy := y0
	while wy <= y1:
		var wx := x0
		while wx <= x1:
			if clipBody and wy < 1.5:
				wx += 1.0
				continue
			var dx: float = wx - c[0]
			var dy: float = wy - c[1]
			var qa: float = A[8]
			var qb: float = 2.0 * (A[2] * dx + A[5] * dy)
			var qc: float = A[0] * dx * dx + 2.0 * A[1] * dx * dy + A[4] * dy * dy - 1.0
			var disc := qb * qb - 4.0 * qa * qc
			if disc < 0.0:
				wx += 1.0
				continue
			var dz := (-qb + sqrt(disc)) / (2.0 * qa)
			var n := unit([A[0] * dx + A[1] * dy + A[2] * dz, A[3] * dx + A[4] * dy + A[5] * dz, A[6] * dx + A[7] * dy + A[8] * dz])
			plot(int((OY - wy) * BW + (OX + wx)), c[2] + dz, vdot(n, LIGHT), part, mat, wx, wy, 0)
			wx += 1.0
		wy += 1.0


static func useFrame(name: String) -> void:
	curFrameIndex = FRAME_IDS.find(name)


static func _arm(far: bool, A: Dictionary, sh: Array, up: int, el: int, fo: int, ha: int, nameU: String, nameF: String) -> void:
	curDim = 1 if far else 0
	useFrame(nameU)
	sphere(sh, 2.5, up, 0)
	sweep(sh, A.joint, 2.1, 1.6, up, 0)
	sphere(A.joint, 1.45, el, 1)
	useFrame(nameF)
	sweep(A.joint, A.end, 1.6, 1.2, fo, 0, 0.15)
	sphere(A.end, 1.9, ha, 0)
	curDim = 0


static func _leg(B: Dictionary, L: Dictionary, hip: Array, th: int, kn: int, sh: int, fo: int, nameT: String, nameS: String, nameFt: String) -> void:
	useFrame(nameT)
	sweep(hip, L.joint, 3.2, 2.2, th, 0)
	sphere(L.joint, 1.9, kn, 1)
	useFrame(nameS)
	sweep(L.joint, L.end, 2.15, 1.4, sh, 0, 0.4)
	useFrame(nameFt)
	var R: Array = B[nameFt].R
	var a: Array = B[nameFt].t
	sweep(add(a, mv(R, [-1.5, -0.6, 0.0])), add(a, mv(R, [4.6, -1.1, 0.0])), 1.7, 1.25, fo, 0)


static func drawBody(S: Dictionary) -> void:
	var B: Dictionary = S.B
	useFrame("pelvis")
	ellipsoid(add(B.pelvis.t, mv(B.pelvis.R, [0.0, -0.2, 0.0])), B.pelvis.R, [2.9, 2.6, 4.2], PART.pelvis, 0)
	useFrame("waist")
	sweep(B.pelvis.t, B.chest.t, 3.0, 3.3, PART.waist, 1)
	useFrame("chest")
	ellipsoid(add(B.chest.t, mv(B.chest.R, [0.2, 0.9, 0.0])), B.chest.R, [3.4, 4.2, 5.5], PART.chest, 0)
	useFrame("neck")
	sweep(B.neck.t, add(B.neck.t, mv(B.head.R, [0.0, 1.6, 0.0])), 1.25, 1.15, PART.neck, 1)
	useFrame("head")
	ellipsoid(B.head.t, B.head.R, [3.0, 3.3, 2.8], PART.head, 0)
	ellipsoid(add(B.head.t, mv(B.head.R, [0.85, -0.45, 0.0])), B.head.R, [2.4, 2.7, 2.35], PART.face, 0)
	_arm(false, S.armN, S.sN, PART.upperN, PART.elbowN, PART.foreN, PART.handN, "upperN", "foreN")
	_arm(true, S.armF, S.sF, PART.upperF, PART.elbowF, PART.foreF, PART.handF, "upperF", "foreF")
	_leg(B, S.legN, S.hipN, PART.thighN, PART.kneeN, PART.shinN, PART.footN, "thighN", "shinN", "footN")
	_leg(B, S.legF, S.hipF, PART.thighF, PART.kneeF, PART.shinF, PART.footF, "thighF", "shinF", "footF")


# ---- what they hold: drawn along the handle from the fist, through the same depth buffer
class Along:
	extends RefCounted
	var H: Array
	var axis: Array
	var side: Array
	var part: int
	var n: Array

	func _init(h: Array, ax: Array, sd: Array, pt: int) -> void:
		H = h
		axis = ax
		side = sd
		part = pt
		n = Self.cross(ax, sd)

	## JS T(i, k, c, lift): a weapon pixel i along the handle, k across it, lifted off its plane.
	func T(i: float, k: float, c: int, lift: float = 0.0) -> void:
		var x: float = H[0] + axis[0] * i + side[0] * k + n[0] * lift
		var y: float = H[1] + axis[1] * i + side[1] * k + n[1] * lift
		var z: float = H[2] + axis[2] * i + side[2] * k + n[2] * lift
		var wx := Px.round(x)
		var wy := Px.round(y)
		if Self.clipWeapon and wy < 0.0:
			return
		var idx := int((Self.OY - wy) * Self.BW + (Self.OX + wx))
		if idx < 0 or idx >= Self.BW * Self.BH:
			return
		Self.curFrameIndex = -1
		Self.plot(idx, z + 0.05, 2.0, part, 2, wx, wy, c)

	## JS T.at(i, k).
	func at(i: float, k: float) -> Array:
		return [H[0] + axis[0] * i + side[0] * k, H[1] + axis[1] * i + side[1] * k, H[2] + axis[2] * i + side[2] * k]


static func blade(T: Along, from: float, length: float, w: float) -> void:
	var i := from
	while i <= from + length + 0.01:
		var r := i - from
		var wd := maxf(0.0, ((length - r) / 5.0) * w) if r > length - 5.0 else w
		var k := -wd
		while k <= wd + 0.01:
			T.T(i, k, STEEL.hi if k < -w * 0.4 else (STEEL.d if k > w * 0.4 else STEEL.a))
			k += 0.4
		i += 0.4


static func haft(T: Along, from: float, to: float, a: int, d: int, r: float = 0.8) -> void:
	var i := from
	while i <= to:
		var k := -r
		while k <= r + 0.01:
			T.T(i, k, d if k > 0.1 else a)
			k += 0.4
		i += 0.4


static func _bowLine(A: Array, B: Array, c: Variant) -> void:
	var n := maxi(2, ceili(vlen(sub(B, A)) / 0.4))
	var Z: int = STEEL.a
	for k in n + 1:
		var P := add(A, mul(sub(B, A), k / float(n)))
		var wx := Px.round(P[0])
		var wy := Px.round(P[1])
		var idx := int((OY - wy) * BW + (OX + wx))
		curFrameIndex = -1
		plot(idx, P[2] + 0.05, 2.0, PART.weapon, 2, wx, wy, c if c != null else Z)


static func drawWeapon(name: String, T: Along, q: Dictionary, off: Array) -> void:
	match name:
		"sword":
			var end := -6.5 if q.get("two") else -2.6
			haft(T, end, 2.2, STEEL.grip, STEEL.gripD)
			var k := -1.4
			while k <= 1.4:
				T.T(end - 0.4, k, STEEL.gold)
				k += 0.4
			k = -4.6
			while k <= 4.6:
				T.T(2.6, k, STEEL.goldD if absf(k) > 3.8 else STEEL.gold)
				T.T(3.0, k, STEEL.goldD)
				k += 0.4
			blade(T, 3.2, 25.0, 2.2)
		"greatsword":
			haft(T, -7.2, 2.2, STEEL.grip, STEEL.gripD)
			var k := -1.8
			while k <= 1.8:
				T.T(-7.6, k, STEEL.gold)
				k += 0.4
			k = -6.6
			while k <= 6.6:
				T.T(2.6, k, STEEL.goldD if absf(k) > 5.6 else STEEL.gold)
				T.T(3.0, k, STEEL.goldD)
				k += 0.4
			blade(T, 3.2, 31.0, 3.0)
			var i := 4.0
			while i <= 28.0:
				T.T(i, 0.0, STEEL.b)
				i += 0.4
		"dagger":
			haft(T, -2.4, 1.8, STEEL.grip, STEEL.gripD)
			var k := -2.6
			while k <= 2.6:
				T.T(2.2, k, STEEL.goldD)
				k += 0.4
			blade(T, 2.6, 10.0, 1.3)
		"spear":
			haft(T, -18.0, 36.0, STEEL.wood, STEEL.woodD, 0.5)
			blade(T, 36.0, 11.0, 2.0)
			var k := -2.4
			while k <= 2.4:
				T.T(36.0, k, STEEL.goldD)
				k += 0.4
		"hammer":
			for lift in [-0.8, 0.0, 0.8]:
				var i := -10.0
				while i <= 18.0:
					var k := -0.8
					while k <= 0.81:
						T.T(i, k, STEEL.woodD if k > 0.1 else STEEL.wood, lift)
						k += 0.4
					i += 0.4
			# the head is a block: its two faces, and the steel between them
			var i := 18.0
			while i <= 28.0:
				var k := -9.0
				while k <= 9.0:
					var face: int = (STEEL.a if k < 0.0 else STEEL.d) if absf(k) > 7.4 else (STEEL.hi if i < 20.0 else (STEEL.d if i > 26.4 else (STEEL.gold if absf(k) < 2.0 else STEEL.b)))
					T.T(i, k, face, 4.5)
					T.T(i, k, face, -4.5)
					if i < 18.4 or i > 27.6 or absf(k) > 8.6:
						var l := -4.0
						while l <= 4.0:
							T.T(i, k, STEEL.a if k < 0.0 else (STEEL.d if i > 27.6 else STEEL.b), l)
							l += 0.4
					k += 0.4
				i += 0.4
		"scythe":
			haft(T, -16.0, 31.0, STEEL.dark, STEEL.darkD, 0.5)
			var j := 0.0
			while j <= 28.0:
				var u := j / 28.0
				var w := 3.2 * (1.0 - u) + 0.3
				var b := 31.5 - u * u * 12.0
				var k := -w
				while k <= w:
					T.T(b + k, j + 0.8, STEEL.hi if k > w * 0.3 else (STEEL.d if k < -w * 0.4 else STEEL.b))
					k += 0.4
				j += 0.4
		"claw":
			for q0 in [-2.4, 0.0, 2.4]:
				var i := 2.0
				while i <= 9.5:
					var u := (i - 2.0) / 7.5
					var k: float = q0 + u * u * 1.8
					T.T(i, k, STEEL.hi if u > 0.55 else STEEL.a)
					if u < 0.6:
						T.T(i, k + 0.8, STEEL.d)
					i += 0.4
		"bow":
			var u := -1.0
			while u <= 1.001:
				var k := u * 17.0
				var i := 6.0 * (1.0 - u * u) - 1.0
				T.T(i, k, STEEL.goldD if absf(u) > 0.85 else STEEL.wood)
				T.T(i + 0.8, k, STEEL.woodD)
				u += 0.025
			var tipA := T.at(-1.0, -17.0)
			var tipB := T.at(-1.0, 17.0)
			var mid: Array = off if q.get("pull") else T.at(-1.0, 0.0)
			_bowLine(tipA, mid, null)
			_bowLine(tipB, mid, null)
			if q.get("nocked"):
				var tip := T.at(13.0, 0.0)
				_bowLine(mid, tip, STEEL.wood)
				var i := 9.0
				while i <= 13.0:
					var k := -(13.0 - i) * 0.45
					while k <= (13.0 - i) * 0.45:
						T.T(i, k, STEEL.hi)
						k += 0.4
					i += 0.4
		"pistol":
			var i := -1.0
			while i <= 9.5:
				var k := -4.2
				while k <= -2.4:
					T.T(i, k, STEEL.a if k < -3.6 else (STEEL.d if k > -2.9 else STEEL.b))
					k += 0.4
				i += 0.4
			i = -1.2
			while i <= 1.2:
				var k := -2.4
				while k <= 2.4:
					T.T(i, k, STEEL.gripD)
					k += 0.4
				i += 0.4
			T.T(9.0, -4.6, STEEL.hi)
		"launcher":
			var i := -14.0
			while i <= 22.0:
				var k := -6.0
				while k <= -1.0:
					T.T(i, k, STEEL.oliveA if k < -4.8 else (STEEL.oliveD if k > -2.2 else (STEEL.gold if absf(i - 3.0) < 1.4 else STEEL.olive)))
					k += 0.4
				i += 0.4
			var k := -6.8
			while k <= -0.2:
				T.T(22.4, k, STEEL.b)
				T.T(-14.4, k, STEEL.d)
				k += 0.4
		"handle":
			haft(T, -2.6, 6.0, STEEL.grip, STEEL.gripD)
			var k := -1.6
			while k <= 1.6:
				T.T(-3.0, k, STEEL.gold)
				T.T(6.4, k, STEEL.gold)
				k += 0.4


# ---- flat tones, seams, and one clean ink line
static func _dim(part: int) -> int:
	return 1 if (part >= PART.upperF and part <= PART.handF) else (1 if (part >= PART.thighF and part <= PART.footF) else 0)


static func _toneOf(v: float, part: int) -> int:
	var t := 0 if v > 0.8 else (1 if v > 0.42 else (2 if v > 0.08 else 3))
	return mini(3, t + _dim(part))


static func _srcFor(i: int, B: Dictionary, restFrames: Variant) -> int:
	var f := Fr[i]
	if f < 0 or restFrames == null:
		return -1
	var name: String = FRAME_IDS[f]
	var A: Dictionary = B[name]
	var R0: Dictionary = restFrames[name]
	var wx := (i % BW) - OX
	var wy := OY - floori(i / float(BW))
	var P := [float(wx), float(wy), Zb[i]]
	var lp := tv(A.R, sub(P, A.t))
	var rp := add(R0.t, mv(R0.R, lp))
	var c := int(Px.round(rp[0])) + 12
	var r := 38 - int(Px.round(rp[1]))
	return -1 if (c < 0 or r < 0 or c >= W0 or r >= H0) else r * W0 + c


static func finish(S: Dictionary, restFrames: Variant) -> Dictionary:
	var N := BW * BH
	var tones := {}
	for i in touched:
		tones[i] = _toneOf(Tone[i], Part[i])
	# a lone pixel of a tone, with no neighbour like it on the same part, takes its neighbours' tone
	for i in touched:
		if Mat[i] == 2:
			continue
		var t: int = tones[i]
		var votes := [0, 0, 0, 0]
		var same := false
		for d in [-1, 1, -BW, BW]:
			var j: int = i + d
			if j < 0 or j >= N or Part[j] != Part[i] or not tones.has(j):
				continue
			var u: int = tones[j]
			votes[u] += 1
			if u == t:
				same = true
		if not same and (votes[0] > 0 or votes[1] > 0 or votes[2] > 0 or votes[3] > 0):
			tones[i] = votes.find(votes.max())
	for i in touched:
		if Mat[i] == 2:
			continue
		Col[i] = (CORE if Mat[i] == 1 else SHELL)[tones[i]]
	# where two parts meet: a soft seam if they touch, ink if one stands in front of the other
	var marks := {}
	for i in touched:
		for d in [1, BW]:
			var j: int = i + d
			if j >= N or Part[j] == 0 or Part[j] == Part[i]:
				continue
			var far: int = i if Zb[i] < Zb[j] else j
			var dz := absf(Zb[i] - Zb[j])
			var steel := Mat[i] == 2 or Mat[j] == 2
			if Mat[far] == 2 and dz < 1.0:
				continue
			var ink := steel or dz > 2.2
			if ink:
				marks[far] = INK
			elif not marks.has(far):
				marks[far] = SEAM
	for i in marks:
		Col[i] = marks[i]
	# the mark on his chest, when it's facing us
	var B: Dictionary = S.B
	var chestAt := add(B.chest.t, mv(B.chest.R, [3.0, 1.6, -1.8]))
	if mv(B.chest.R, [1.0, 0.0, 0.0])[2] > 0.15:
		var i := int((OY - Px.round(chestAt[1])) * BW + (OX + Px.round(chestAt[0])))
		if i >= 0 and i < N and Part[i] == PART.chest:
			Col[i] = MARK
	# the outline, and everything into a small list of pixels
	var list := touched.duplicate()
	var ring := {}
	for i in list:
		for d in [-1, 1, -BW, BW]:
			var j: int = i + d
			if j >= 0 and j < N and Part[j] == 0 and not ring.has(j):
				ring[j] = i
	var n: int = list.size() + ring.size()
	var out := {"n": n, "xs": PackedInt32Array(), "ys": PackedInt32Array(), "color": PackedInt64Array(), "src": PackedInt32Array(), "ink": PackedByteArray()}
	for k in ["xs", "ys", "color", "src", "ink"]:
		out[k].resize(n)
	var k := 0
	var x0 := 1000000000
	var y0 := 1000000000
	var x1 := -1000000000
	var y1 := -1000000000
	for pass_ in 2:
		var items: Array = list if pass_ == 0 else ring.keys()
		for idx in items:
			var i: int = idx
			var c: int = Col[i] if pass_ == 0 else INK
			var s := _srcFor(i if pass_ == 0 else ring[i], B, restFrames)
			var x := (i % BW) - OX
			var y := floori(i / float(BW)) - OY
			out.xs[k] = x
			out.ys[k] = y
			out.color[k] = c
			out.src[k] = s
			out.ink[k] = 1 if (pass_ == 1 or c == INK) else 0
			if x < x0: x0 = x
			if x > x1: x1 = x
			if y < y0: y0 = y
			if y > y1: y1 = y
			k += 1
	var zs := 0.0
	for i in list:
		zs += Zb[i]
	out.x0 = x0
	out.y0 = y0
	out.x1 = x1
	out.y1 = y1
	out.z = zs / list.size() if list.size() else 0.0
	for i in list:
		Part[i] = 0
	touched.clear()
	return out


## The whole figure turned about the vertical through the feet.
static func turnAll(S: Dictionary, a: float) -> void:
	var R := rotY(-a)
	for name in S.B:
		var f: Dictionary = S.B[name]
		f.t = mv(R, f.t)
		f.R = mm(R, f.R)
	for key in ["armN", "armF", "legN", "legF"]:
		var A: Dictionary = S[key]
		A.joint = mv(R, A.joint)
		A.end = mv(R, A.end)
	for key in ["sN", "sF", "hipN", "hipF", "axis", "side"]:
		S[key] = mv(R, S[key])


static func _whole(q: Dictionary) -> float:
	return float(_nn(q.get("yaw"), 0.0)) + (PI if q.get("face") == -1 else 0.0)


static func render(pose: Dictionary) -> Dictionary:
	_setup()
	var S := solve(pose)
	var q: Dictionary = S.q
	var whole := _whole(q)
	if whole:
		turnAll(S, whole)
	var air: bool = float(_nn(q.get("y"), 0.0)) < -0.5
	clipBody = not air
	clipWeapon = not air
	drawBody(S)
	clipBody = false
	if S.W != null:
		drawWeapon(q.weapon, Along.new(S.armN.end, S.axis, S.side, PART.weapon), q, S.armF.end)
	if S.OW != null:
		var sb: float = _nn(q.get("sb"), PI)
		var ax := [cos(sb), -sin(sb), 0.0]
		var sd := [-sin(sb), -cos(sb), 0.0]
		if whole:
			var R := rotY(-whole)
			ax = mv(R, ax)
			sd = mv(R, sd)
		drawWeapon(q.offWeapon, Along.new(S.armF.end, ax, sd, PART.offWeapon), q, S.armF.end)
	clipWeapon = false
	return finish(S, REST_FRAMES)


static func _keyOf(p: Dictionary) -> String:
	var s := "air," if float(_nn(p.get("y"), 0.0)) < -0.5 else ""
	var keys := p.keys()
	keys.sort()
	for k in keys:
		var v: Variant = p[k]
		if v == null or k == "x" or k == "y" or k == "ghost":
			continue
		var t: String
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			t = str(int(Px.round(v * 20.0))) if k in ["sa", "sb", "wl", "yaw", "turn"] else str(int(Px.round(v)))
		else:
			t = str(v)
		s += str(k) + t + ","
	return s


## How far short of where the pose wants them the hands fall, in px: arms don't stretch.
static func shortfall(pose: Dictionary) -> float:
	_setup()
	var S := solve(pose)
	var q: Dictionary = S.q
	var near := vlen(sub(S.armN.end, [float(q.fx), -q.fy, S.armN.end[2]]))
	var far := 0.0 if q.get("two") else vlen(sub(S.armF.end, [float(q.bx), -q.by, S.armF.end[2]]))
	return maxf(near, far)


## The pixels of a pose: { n, xs, ys, color (unsigned), src, ink, x0, y0, x1, y1, z }, feet at (0, 0).
static func posed(pose: Dictionary) -> Dictionary:
	var key := _keyOf(pose)
	var r: Variant = CACHE.get(key)
	if r == null:
		if CACHE.size() > 6000:
			CACHE.clear()
		r = render(pose)
		CACHE[key] = r
	return r


## The skeleton of a pose, in the same local space as posed(): x right, y down, feet at (0, 0), z toward the viewer.
## { joints: { name: [x, y, z] }, bones: [[from, to], ...], handles: [name, ...] }.
static func skeleton(pose: Dictionary) -> Dictionary:
	_setup()
	var S := solve(pose)
	var q: Dictionary = S.q
	var whole := _whole(q)
	if whole:
		turnAll(S, whole)
	var B: Dictionary = S.B
	var J := {
		"pelvis": B.pelvis.t, "waist": B.waist.t, "chest": B.chest.t, "neck": B.neck.t, "head": B.head.t, "crown": add(B.head.t, mv(B.head.R, [0.0, 3.3, 0.0])),
		"shoulderN": S.sN, "elbowN": S.armN.joint, "handN": S.armN.end, "shoulderF": S.sF, "elbowF": S.armF.joint, "handF": S.armF.end,
		"hipN": S.hipN, "kneeN": S.legN.joint, "ankleN": S.legN.end, "toeN": add(B.footN.t, mv(B.footN.R, [4.6, -1.1, 0.0])),
		"hipF": S.hipF, "kneeF": S.legF.joint, "ankleF": S.legF.end, "toeF": add(B.footF.t, mv(B.footF.R, [4.6, -1.1, 0.0])),
	}
	var joints := {}
	for k in J:
		joints[k] = [J[k][0], -J[k][1], J[k][2]]
	var bones := [["pelvis", "waist"], ["waist", "chest"], ["chest", "neck"], ["neck", "head"], ["head", "crown"], ["chest", "shoulderN"], ["shoulderN", "elbowN"], ["elbowN", "handN"], ["chest", "shoulderF"], ["shoulderF", "elbowF"], ["elbowF", "handF"], ["pelvis", "hipN"], ["hipN", "kneeN"], ["kneeN", "ankleN"], ["ankleN", "toeN"], ["pelvis", "hipF"], ["hipF", "kneeF"], ["kneeF", "ankleF"], ["ankleF", "toeF"]]
	return {"joints": joints, "bones": bones, "handles": ["handN", "handF", "ankleN", "ankleF"]}


## The figure taken apart: each part drawn alone, with its own outline, and where its middle is.
static func posedParts(pose: Dictionary) -> Array:
	var out := []
	for name in PART:
		onlyPart = PART[name]
		var r := render(pose)
		onlyPart = 0
		if not r.n:
			continue
		var cx := 0.0
		var cy := 0.0
		for i in r.n:
			cx += r.xs[i]
			cy += r.ys[i]
		out.append({"name": name, "part": PART[name], "n": r.n, "xs": r.xs, "ys": r.ys, "color": r.color, "cx": cx / r.n, "cy": cy / r.n, "z": r.z})
	return out
