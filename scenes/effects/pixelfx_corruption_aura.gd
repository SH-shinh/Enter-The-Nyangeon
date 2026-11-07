# 参考 pixelfx status/poisoned 的「毒汗 + 气泡 + 光晕」（MIT），去掉地面脉冲环与身体重绘：
# ENN 的敌人贴图各不相同，身体只保留已有的 tint，本效果只做附着的分泌物/气泡/光。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Corrupted",
	"desc": "Corruption seeps out of the body: purple sweat beads, rises and hisses on the floor; blisters well up and pop; a sick light pulses with it.",
	"tags": ["status", "corruption", "debuff", "loop"],
	"size": [72, 72],
	"origin": [36, 64],
	"duration": 1.6,
	"loop": true,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#0b0614", "#1a0b2e", "#2c1250", "#4a1f8a", "#6d2dff", "#9a6bff", "#c9a6ff", "#f0e6ff"],
		"seed": 5,
	},
}

const D := 1.6
const TICK := 0.8
const G := 760.0


static func since(t: float) -> float:
	return fmod(fmod(t, TICK) + TICK, TICK)


# 虚拟身体框内的固定点位（无 actor 遮罩，用 seed 生成一次）
static var SPOTS := {}


static func spots(o: Dictionary) -> Dictionary:
	var key := float(o.seed)
	if SPOTS.has(key):
		return SPOTS[key]
	var R := Px.Rng.new(key * 7.0 + 3.0)
	var sweat := []
	for i in 7:
		sweat.append([R.range(-10.0, 10.0), R.range(-34.0, -14.0)])
	var rows := []
	for _row in 2:
		var pts := []
		for _j in 4:
			pts.append([R.range(-8.0, 8.0), R.range(-30.0, -12.0), R.range(1.1, 1.8)])
		rows.append(pts)
	var out := {"sweat": sweat, "rows": rows}
	SPOTS[key] = out
	return out


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var P := Px.fit(o.palette, 8)
	var S := spots(o)
	var ph := since(t)
	var tick := floori(t / TICK) % 2

	# 毒汗：聚拢 → 沿身体下滑 → 落地嘶散
	for i in S.sweat.size():
		var sx: float = S.sweat[i][0]
		var sy: float = S.sweat[i][1]
		var per := D / 2.0
		var age := fmod(fmod(t - i * 0.37, per) + per, per)
		var gather := 0.35
		if age < gather:
			var k := age / gather
			var run := Px.round(k * 2.0)
			p.px(sx, sy + run, P[7] if k > 0.5 else P[6])
			if k > 0.5:
				p.px(sx, sy + run - 1.0, P[5])
			continue
		var f := age - gather
		var fall_h := -1.0 - (sy + 2.0)
		var tf := sqrt((2.0 * maxf(1.0, fall_h)) / G)
		if f < tf:
			var y := sy + 2.0 + 0.5 * G * f * f
			p.line(sx, y - minf(3.0, G * f * 0.012), sx, y, P[4])
			p.px(sx, y, P[7])
			continue
		var h := f - tf
		if h > 0.4:
			continue
		var k2 := h / 0.4
		p.line(sx - 1.0 - k2 * 2.0, -1.0, sx + 1.0 + k2 * 2.0, -1.0, P[6] if k2 < 0.4 else P[4], 1.2 - k2)
		for j in 3:
			p.dot(sx + (j - 1) * (2.0 + 3.0 * k2), -2.0 - j % 2 - 5.0 * k2 * (1.0 - k2), P[6], 1.0 - k2)
		p.disc(sx + sin(k2 * 6.0) * 1.5, -3.0 - k2 * 6.0, 1.0 + 1.5 * k2, P[5], 0.35 * (1.0 - k2))
		p.glow(sx, -1.5, 5.0, P[5], 0.35 * (1.0 - k2))

	# 气泡：两排轮换，膨胀后破裂
	for bl: Array in S.rows[tick]:
		var bx: float = bl[0]
		var by: float = bl[1]
		var br: float = bl[2]
		var grow := Px.clamp(ph / 0.16)
		var popped := ph > 0.38
		if not popped:
			var r := br * grow
			p.circle(bx, by, r + 0.6, P[4])
			p.circle(bx - 0.2, by - 0.2, r, P[6])
			if r > 0.8:
				p.px(bx - 0.5, by - 0.8, WHITE)
			p.glow(bx, by, 6.0, P[5], 0.45 * grow)
		elif ph < 0.56:
			var k3 := (ph - 0.38) / 0.18
			for j in 6:
				var an: float = (j / 6.0) * TAU + bx
				var d: float = br + 0.5 + k3 * 3.5
				p.dot(bx + cos(an) * d, by + sin(an) * d - k3 * 2.0, P[6] if j % 2 else P[5], 1.2 - k3)
			p.glow(bx, by, 6.0, P[6], 0.4 * (1.0 - k3))

	# 光晕：随 0.8s 的 tick 起伏
	# 只在脚边给一圈地面光晕：躯干不加不透明光盘，避免盖住敌人贴图
	p.glow(0.0, -3.0, 18.0, P[5], 0.30 + 0.20 * exp(-ph / 0.18))
	p.glow(0.0, -2.0, 14.0, P[4], 0.22)
