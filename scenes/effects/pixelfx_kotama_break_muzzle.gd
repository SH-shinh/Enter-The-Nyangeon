# 参考 pixelfx impacts/crit-hit + impacts/hit-spark + explosions/plasma-explosion（MIT）：
# 破隐首枪的枪口爆发。去 actor、无地面环、无烟柱；白色星爆 + 青蓝冲击环 + 前向火花。
# 绘制坐标以 meta.origin 为 (0,0)，局部 +X 为射击方向。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const WHITE := Px.WHITE

const D := 14.0 / 45.0
const PALETTE := [
	"#06111d",
	"#0d2b42",
	"#155a7a",
	"#28a8d8",
	"#6fe3ff",
	"#bff7ff",
	"#fff0b8",
	"#ffffff",
]

static var meta := {
	"name": "Kotama break muzzle",
	"desc": "A break-shot muzzle burst: white star flash, cyan holo shock ring, forward spark cone and short tracer streaks; no actor and no ground ring.",
	"tags": ["muzzle", "flash", "break", "crit", "holo", "directional", "one-shot", "kotama"],
	"size": [160, 96],
	"origin": [24, 48],
	"duration": D,
	"loop": false,
	"fps": 45,
	"bg": "sky",
	"options": {"palette": PALETTE, "seed": 17},
}


static func _diamond(p: Px.Painter, x: float, y: float, r: int, C: Array) -> void:
	for dy in range(-r - 1, r + 2):
		for dx in range(-r - 1, r + 2):
			var m: int = absi(dx) + absi(dy)
			if m <= r:
				p.dot(x + dx, y + dy, WHITE, 1.0)
			elif m == r + 1:
				p.dot(x + dx, y + dy, int(C[5]), 0.7)


static func _ray(p: Px.Painter, angle: float, length: float, width: float, color: int, alpha: float) -> void:
	var d := 0.0
	while d <= length:
		var u: float = d / maxf(1.0, length)
		var a: float = alpha * (1.0 - u * 0.7)
		var c: int = WHITE if u < 0.28 else color
		p.dot(cos(angle) * d, sin(angle) * d, c, a)
		var half: int = int(maxf(0.0, width * (1.0 - u)) * 0.5)
		if half > 0:
			for s in range(-half, half + 1):
				p.dot(cos(angle) * d - sin(angle) * float(s), sin(angle) * d + cos(angle) * float(s), c, a * 0.6)
		d += 1.0


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	if t >= D:
		return
	var C := Px.fit(o.palette, 8)
	var R := Px.Rng.new(float(o.seed))
	var q: float = clampf(t / D, 0.0, 1.0)
	var early: float = maxf(0.0, 1.0 - t / 0.065)
	var body: float = maxf(0.0, 1.0 - q)

	# 1) 白色枪口闪光：最早期压过普通橙色底火。
	if t < 0.065:
		var k: float = early
		p.circle(0.0, 0.0, 3.0 + 8.0 * k, int(C[5]), 0.75 * k)
		p.circle(0.0, 0.0, 1.5 + 4.5 * k, WHITE, 0.9 * k)
		p.glow(0.0, 0.0, 26.0, int(C[5]), 0.7 * k)
		p.glow(0.0, 0.0, 9.0, WHITE, 0.8 * k)
		_diamond(p, 0.0, 0.0, 5, C)

	# 2) 星形爆点：前向长、后向短，斜向两长两短。
	if t < 0.22:
		var sk: float = Px.Ease.outCubic(clampf(t / 0.12, 0.0, 1.0))
		var fade: float = 1.0 - clampf((t - 0.08) / 0.14, 0.0, 1.0)
		var L: float = 9.0 + 42.0 * sk
		var col: int = int(C[5]) if t < 0.08 else int(C[4])
		Px.flare(p, 0.0, 0.0, 10.0 + 24.0 * sk, fade * 0.95, C)
		Px.sparkle(p, 0.0, 0.0, 8 + int(7.0 * sk), int(C[5]), WHITE, 0.9)
		_ray(p, 0.0, L * 1.35, 3.0, col, fade)
		_ray(p, PI, L * 0.40, 2.4, int(C[4]), fade * 0.8)
		_ray(p, -PI * 0.5, L * 0.62, 2.6, col, fade * 0.9)
		_ray(p, PI * 0.5, L * 0.52, 2.4, int(C[5]), fade * 0.85)
		_ray(p, -PI * 0.25, L * 0.50, 1.4, int(C[4]), fade * 0.7)
		_ray(p, PI * 0.25, L * 0.42, 1.4, int(C[4]), fade * 0.65)

	# 3) 青蓝冲击环，碎成弧段而不是规则整圆。
	if t >= 0.025 and t < 0.30:
		var rr: float = 4.0 + 44.0 * Px.Ease.outCubic(clampf((t - 0.025) / 0.22, 0.0, 1.0))
		var ring_fade: float = clampf(1.0 - (t - 0.025) / 0.26, 0.0, 1.0)
		p.ring(0.0, 0.0, rr, 2.5, WHITE if t < 0.09 else int(C[4]), ring_fade * 0.55)
		p.glowRing(0.0, 0.0, rr, 2.0, int(C[4]), ring_fade * 0.35)
		var segs := 7
		for i in segs:
			var base: float = float(i) * TAU / float(segs)
			var gap: float = 0.15 + 0.10 * float(i % 3)
			var a: float = base + gap
			var end: float = base + TAU / float(segs) - gap * 0.8
			var steps: int = int(maxf(7.0, rr * 1.3))
			for j in steps:
				var u: float = float(j) / float(steps)
				var ang: float = a + (end - a) * u
				var c: int = WHITE if t < 0.08 else int(C[4] if i % 2 == 0 else C[5])
				p.dot(cos(ang) * rr, sin(ang) * rr, c, ring_fade * (0.95 - 0.25 * u))
		p.glow(0.0, 0.0, 30.0 + 20.0 * ring_fade, int(C[4]), 0.28 * ring_fade)

	# 4) 前向火花锥 + 少量后喷火花；无地面反弹。
	var spark_count := 24
	for i in spark_count:
		var back: bool = i >= 19
		var ang: float = (PI if back else 0.0) + R.range(-0.62, 0.62)
		var speed: float = R.range(150.0, 420.0) * (0.55 if back else 1.0)
		var life: float = R.range(0.18, 0.32)
		if t >= life:
			continue
		var u: float = t / life
		var dist: float = speed * t
		var x: float = cos(ang) * dist
		var y: float = sin(ang) * dist - 10.0 * t * (1.0 - u)
		var col: int = WHITE if u < 0.35 else int(C[6] if i % 4 == 0 else C[5])
		p.dot(x, y, col, (1.0 - u) * (0.95 if not back else 0.7))
		if u < 0.7:
			p.dot(x - cos(ang) * 3.0, y - sin(ang) * 3.0, int(C[5]), (1.0 - u) * 0.45)
			p.glow(x, y, 3.0, int(C[5]), (1.0 - u) * 0.22)

	# 5) 短前向速度线，沿 +X 拉出爆发感。
	if t < 0.16:
		var line_fade: float = 1.0 - t / 0.16
		for i in 5:
			var yy: float = -4.0 + float(i) * 2.0
			var start: float = 8.0 + float(i) * 2.0
			var length: float = (40.0 + float(i) * 10.0) * (0.5 + 0.5 * line_fade)
			var d: float = start
			while d < start + length:
				p.dot(d, yy, int(C[6]) if i % 2 else WHITE, line_fade * 0.6)
				d += 1.0

	# 6) 全息扫描碎片：中后段横向短划线，像破隐残像。
	if t >= 0.08 and t < 0.30:
		var shard_fade: float = 1.0 - clampf((t - 0.08) / 0.22, 0.0, 1.0)
		for i in 9:
			var ang: float = float(i) * TAU / 9.0 + 0.17 * float(i % 2)
			var rad: float = 16.0 + 22.0 * R.range(0.2, 1.0)
			var cx: float = cos(ang) * rad
			var cy: float = sin(ang) * rad
			var w: int = 3 + i % 3
			for s in range(w):
				p.dot(cx + float(s), cy, int(C[4]), shard_fade * 0.55)

	# 7) 冷色余辉收尾。
	if t >= 0.12:
		p.glow(0.0, 0.0, 34.0 * body + 4.0, int(C[4]), 0.28 * body)
