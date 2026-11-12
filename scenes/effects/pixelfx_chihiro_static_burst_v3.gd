# 参考 pixelfx lightning/thunderclap 的「范围电爆」（MIT，see NOTICE.md / third_party/pixelfx-godot）。
# 相对原版：① 去 actor（bodyless，删 p.mask/act）；② CY=0、地面环 SY=1.0 正圆（俯视）；
# ③ 画布 352×352 / REACH 160（运行时 scale=2.0 覆盖 320 半径，四边留 16px，环完整不裁）；
# ④ 蓝紫感电调色（对齐 shock_chain_arc 的 BODY/CORE/SPARK），保留原版 Particles/Lights（火花/烟/尘埃/落点光）。
# port-of: src/fx/lightning/thunderclap.js@6fac4bbf932c9ad91d01085d257b97fcdd309c09
extends "res://addons/pixelfx/core/effect.gd"

const Px := preload("res://addons/pixelfx/core/px.gd")
const Lib := preload("res://scenes/effects/pixelfx_lightning_lib.gd")
const P := Px.P
const PF := Px.PF
const WHITE := Px.WHITE

const CHIHIRO_SHOCK := ["#0b0614", "#1c1233", "#33205e", "#4a2fa0", "#6a4cff", "#8f7bff", "#c9bcff", "#f5f2ff"]
const CLAP := 0.08
const REACH_MAX := 160.0
const BK := [1.0, 0.7, 0.95, 0.5, 0.8, 0.3]
static var DUST := Px.hex("#6e6382")
static var STONE := Px.ramp(["#655b7a", "#4a4263", "#342d45"])
static var ASH := Px.hex("#5b5566")

static var meta := {
	"name": "Chihiro static burst",
	"desc": "A static nova round the caster: white flash, forked bolts, a circular shock ring, sparks and dust.",
	"tags": ["lightning", "electric", "nova", "aoe", "one-shot", "chihiro"],
	"size": [352, 352],
	"origin": [176, 176],
	"duration": 0.75,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": CHIHIRO_SHOCK,
		"sparks": Lib.PLASMA,
		"reach": REACH_MAX,
		"seed": 6,
	},
}

var o: Dictionary
var C: Array
var R: Px.Rng
var REACH: float
var ps: Px.Particles
var hot: Px.Particles
var lights: Px.Lights
var bolts: Array
var t := 0.0
var clapped := false
var landed: Array


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	REACH = float(o.reach)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": o.get("sparks")})
	hot = Px.Particles.new({"rng": R, "ground": floor_, "sparks": o.get("sparks")})
	lights = Px.Lights.new()
	bolts = Px.arr(8, func(i):
		var ang := (float(i) / 8.0) * TAU + R.range(-0.28, 0.28)
		var L := REACH * R.range(0.6, 1.0)
		return {"x1": cos(ang) * L, "y1": sin(ang) * L, "t0": CLAP + R.range(0.0, 0.06)})
	landed = bolts.map(func(_b): return false)


func front(t_: float) -> float:
	return 0.0 if t_ < CLAP else 8.0 + (REACH - 8.0) * Px.Ease.outCubic(Px.clamp((t_ - CLAP) / 0.5))


func update(dt: float) -> void:
	t += dt
	# 起手：火花向中心聚拢
	if t < CLAP and R.chance(60.0 * dt):
		var a := R.range(0.0, TAU)
		var d := R.range(16.0, 34.0)
		var T := R.range(0.07, 0.1)
		var v := (d * 3.0) / (exp(3.0 * T) - 1.0)
		ps.spawn(P.STREAK, cos(a) * d, sin(a) * d, -cos(a) * v, -sin(a) * v, T, C[6] if R.chance(0.5) else C[5])
	if t >= CLAP and not clapped:
		clapped = true
		lights.add(0.0, 0.0, 120.0, C[4], 0.65, 0.45)
		lights.add(0.0, 0.0, 32.0, WHITE, 0.5, 0.07)
		for i in 72:
			var a := R.range(0.0, TAU)
			var sp := R.range(170.0, 380.0)
			ps.spawn(P.SPARK, cos(a) * 6.0, sin(a) * 6.0, cos(a) * sp, sin(a) * sp - 40.0, R.range(0.2, 0.55))
		for i in 10:
			ps.spawn(P.SMOKE, R.range(-8.0, 8.0), R.range(-6.0, 6.0), R.range(-25.0, 25.0), -R.range(10.0, 30.0), R.range(0.8, 1.3), Px.mix(ASH, C[4], 0.35), R.range(4.0, 7.0), R.range(0.05, 0.2))
	# 每条电弧落地：火花 + 光斑
	for i in bolts.size():
		var b: Dictionary = bolts[i]
		if not landed[i] and t >= float(b.t0):
			landed[i] = true
			lights.add(b.x1, b.y1, 46.0, C[4], 0.7, 0.25)
			for j in 14:
				var a := atan2(b.y1, b.x1) + R.range(-1.2, 1.2)
				var sp := R.range(70.0, 240.0)
				ps.spawn(P.SPARK, b.x1, b.y1, cos(a) * sp, sin(a) * sp, R.range(0.2, 0.5))
			for j in 5:
				hot.spawn(P.SPARK, b.x1 + R.range(-2.0, 2.0), b.y1, R.range(-80.0, 80.0), R.range(-120.0, 60.0), R.range(0.4, 0.8))
	# 环扫过地面：扬尘 + 砂砾（径向）
	var fr := front(t)
	if t > CLAP and t < CLAP + 0.5 and fr > 4.0:
		var ang := R.range(0.0, TAU)
		var ca := cos(ang)
		var sa := sin(ang)
		if R.chance(70.0 * dt):
			ps.spawn(P.SMOKE, ca * fr + R.range(-3.0, 3.0), sa * fr + R.range(-3.0, 3.0), ca * R.range(10.0, 40.0), sa * R.range(10.0, 40.0), R.range(0.6, 1.1), DUST, R.range(3.0, 6.0) * (1.0 - 0.4 * (fr / REACH)), 0.0, PF.BIG)
		if R.chance(50.0 * dt):
			ps.spawn(P.GRIT, ca * fr, sa * fr, ca * R.range(10.0, 60.0), sa * R.range(10.0, 60.0), R.range(0.8, 1.3), R.pick(STONE), 2.0 if R.chance(0.3) else 1.0)
	ps.update(dt)
	hot.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var u := (t - CLAP) / 0.5
	if u > 0.0 and u < 1.0:
		Px.band(p, 0.0, 0.0, front(t), 1.0, maxf(2.0, 10.0 * (1.0 - u)), 1.1 - u, [C[1], C[2], C[4], C[6]], null, u < 0.15)
	ps.draw(p, "back")
	hot.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var f := floori(t * 45.0 + 1e-4)
	var u := (t - CLAP) / 0.5
	var a := t - CLAP
	# 起手：中心聚能（保证前几帧非空）
	if t < CLAP:
		var kk := t / CLAP
		p.glow(0.0, 0.0, 14.0 + 12.0 * kk, C[4], 0.3 * kk)
		p.px(0.0, 0.0, C[6])
		return
	# 白闪 + 中心核（bodyless：不再给 actor 上色）
	if a >= 0.0 and a < 0.2:
		var q := a / 0.2
		Px.flare(p, 0.0, 0.0, 50.0 * pow(1.0 - q, 1.4), 0.75 * (1.0 - q), C)
		p.glow(0.0, 0.0, 28.0 * (1.0 - q) + 3.0, C[6], 0.32 * (1.0 - q))
		if a < 0.06:
			p.px(0.0, 0.0, WHITE)
	# 分叉电弧（闪烁两次）
	for i in bolts.size():
		var b: Dictionary = bolts[i]
		var ba := floori((t - float(b.t0)) * 45.0 + 1e-4)
		if t < float(b.t0) or ba >= BK.size():
			continue
		var r := Px.rng(o.seed, 3, i, ba >> 1)
		Lib.stroke(p, Lib.zigzag(r, 0.0, 0.0, b.x1, b.y1, 0.28, 0.45), BK[ba], C, 1.0 if ba == 0 else 0.8, {"hero": ba == 0})
		p.circle(b.x1, b.y1, 3.0 * BK[ba] + 1.0, C[5])
		p.px(b.x1, b.y1, WHITE)
		p.glow(b.x1, b.y1, 20.0, C[5], 0.5 * BK[ba])
	# 正圆冲击环（全圆）+ 空气环
	if u > 0.0 and u < 1.0:
		Px.band(p, 0.0, 0.0, front(t), 1.0, maxf(2.0, 10.0 * (1.0 - u)), 1.0 - u, [C[1], C[2], C[4], C[6]], null, u < 0.15)
		p.glow(0.0, 0.0, front(t) + 8.0, C[4], 0.15 * (1.0 - u))
	# 余波：中心短电弧
	if a > 0.2 and t < 0.75:
		var k := 1.0 - (a - 0.2) / 0.55
		var r := Px.rng(o.seed, 9, f)
		for i in 4:
			var ang := r.range(0.0, TAU)
			var l := r.range(10.0, 28.0)
			Lib.crackle(p, Lib.zigzag(r, cos(ang) * 8.0, sin(ang) * 8.0, cos(ang) * (8.0 + l), sin(ang) * (8.0 + l), 0.4, 0.3), 0.8 * k + 0.1, C, 0.35)
	ps.draw(p, "front")
	hot.draw(p, "front")
	lights.draw(p)
