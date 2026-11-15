# 参考 pixelfx ice/snowflake-burst（MIT）的「迸发」段：
# 保留聚拢 → 白闪 → 十字光条 → 扩散霜环 → 辉光环 → 余冷光；
# 去掉六臂雪花与雪花落地/融化段，并把保留段整体加速 50%（各时间窗 ÷ SPEED）。
# 本项目的迸发量级放大（环半径/环厚/亮度都比参考库大一档），在 640×360 下才读得出来。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const WHITE := Px.WHITE

## 整体加速倍率：保留段的时间窗全部按 1/SPEED 压缩。
const SPEED := 1.5
const D := 1.2
const POP := 0.16 / SPEED
const FLASH := 0.09 / SPEED
const FLARE := 0.30 / SPEED
const RING := 0.42 / SPEED
const AFTER := 1.6 / SPEED
## 迸发中心（画布 140×120、origin 70,106 时在脚底上方 48px）
const CY := -48.0
## 扩散环最大半径与环厚（参考库是 34/2.4，这里放大到 52/3.6）
const RING_MAX := 52.0
const RING_W := 3.6

static var meta := {
	"name": "Frost burst",
	"desc": "The cold pop of a snowflake burst without the flakes: frost gathers, flashes white, throws a ring and flares, then the cold light fades.",
	"tags": ["ice", "frost", "burst", "one-shot"],
	"size": [140, 120],
	"origin": [70, 106],
	"duration": D,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"], "seed": 8},
}


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	if t >= D:
		return
	var C := Px.fit(o.palette, 8)
	var seed := float(o.seed)
	# 1) 聚拢：霜点向心收拢 + 中心微光渐亮（不画雪花形状）
	if t < POP:
		var k := Px.clamp(t / POP)
		for i in 18:
			var ang := (float(i) / 18.0) * TAU + 0.35 + Px.rand(i, seed, 1.0) * 0.22
			var rad := 10.0 + 42.0 * (1.0 - k) + Px.rand(i, seed, 2.0) * 7.0
			var c: int = int(C[6]) if i % 3 else int(C[5])
			p.dot(cos(ang) * rad, CY + sin(ang) * rad * 0.85, c, 0.3 + 0.7 * k)
		p.glow(0.0, CY, 8.0 + 18.0 * k, int(C[5]), 0.35 + 0.45 * k)
		p.circle(0.0, CY, 1.0 + 3.0 * k * k, WHITE)
	# 2) 迸发
	var q := t - POP
	if q >= 0.0 and q < RING * 2.4:
		# 白闪
		if q < FLASH:
			p.circle(0.0, CY, 10.0 * (1.0 - q / FLASH) + 2.0, WHITE)
		# 十字光条（两层：长十字 + 短斜十字）
		if q < FLARE:
			var fk := 1.0 - q / FLARE
			Px.flare(p, 0.0, CY, 36.0 * pow(maxf(0.0, fk), 1.3), fk, C)
			Px.flare(p, 0.0, CY, 18.0 * pow(maxf(0.0, fk), 1.6), fk * 0.7, C)
		# 扩散霜环 + 辉光环（两圈：主环 + 内侧亮环）
		if q < RING:
			var e := Px.Ease.outCubic(q / RING)
			var r := 6.0 + RING_MAX * e
			var ring_c: int = WHITE if q < FLASH else (int(C[6]) if q < RING * 0.5 else int(C[5]))
			p.ring(0.0, CY, r, maxf(1.4, RING_W * (1.0 - e)), ring_c, 1.35 - e)
			p.glowRing(0.0, CY, r, 7.0, int(C[5]), 0.55 * (1.0 - e))
			if q < RING * 0.55:
				p.ring(0.0, CY, r * 0.62, maxf(1.0, 2.0 * (1.0 - e)), int(C[6]), 1.1 - e)
		# 放射霜丝（外扩 + 变淡）
		var u := Px.clamp(q / (RING * 1.8))
		var fade := 1.0 - u
		if fade > 0.0:
			for i in 16:
				var ang := (float(i) / 16.0) * TAU + Px.rand(i, seed, 3.0) * 0.35
				var spd := 0.65 + Px.rand(i, seed, 4.0) * 0.7
				var d := 8.0 + 58.0 * Px.Ease.outCubic(u) * spd
				var x := cos(ang) * d
				var y := CY + sin(ang) * d * 0.85
				p.dot(x, y, WHITE if i % 4 == 0 else int(C[6]), 1.0 * fade)
				p.line(x - cos(ang) * 6.0, y - sin(ang) * 6.0, x, y, int(C[5]), 0.65 * fade)
		# 闪烁点
		for i in 14:
			var tw := maxf(0.0, sin(q * 26.0 + Px.rand(i, seed, 5.0) * TAU))
			if tw < 0.3:
				continue
			var ang2 := (float(i) / 14.0) * TAU + 0.5
			var d2 := 12.0 + 40.0 * Px.rand(i, seed, 6.0)
			p.dot(cos(ang2) * d2, CY + sin(ang2) * d2 * 0.85, WHITE, 1.0 * tw)
	# 3) 余冷光淡出
	if q >= 0.0:
		p.glow(0.0, CY, 56.0, int(C[4]), 0.45 * (1.0 - Px.smooth(POP, POP + AFTER, t)))
