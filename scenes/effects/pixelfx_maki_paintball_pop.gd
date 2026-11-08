# 参考 pixelfx arcane/arcane-missiles（MIT，命中爆点 pop 部分）：
# 白闪 + 十字光条 + 扩散环 + 少量颜料飞溅。绘制坐标以 meta.origin 为 (0,0)。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const WHITE := Px.WHITE

const D := 0.36

static var meta := {
	"name": "Maki paintball pop",
	"desc": "The paint bolt's impact: a flash disc, a cross of light, an expanding ring and a few paint flecks.",
	"tags": ["impact", "paint", "one-shot"],
	"size": [72, 72],
	"origin": [36, 36],
	"duration": 0.36,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#2a0f1c", "#5c1f38", "#a83a63", "#e86a9a", "#ff9cc0", "#ffc4da", "#ffe0ee", "#ffffff"],
		"seed": 11,
	},
}


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	if t >= D:
		return
	var C := Px.fit(o.palette, 8)
	var q := clampf(t / D, 0.0, 1.0)
	# 白闪（小一点，保留色环）
	if q < 0.35:
		var r := 7.0 * (1.0 - q / 0.35) + 1.5
		p.circle(0.0, 0.0, r + 2.0, C[5])
		p.circle(0.0, 0.0, r, WHITE)
	# 十字光条（彩色）
	if q < 0.7:
		var l := 16.0 * (1.0 - q / 0.7) + 3.0
		var d := -l
		while d <= l:
			var a: float = absf(d) / l
			var c: int = WHITE if a < 0.25 else (int(C[6]) if a < 0.55 else int(C[5]))
			p.dot(d, 0.0, c, 1.15 - a)
			p.dot(0.0, d * 0.7, c, 1.15 - a)
			d += 1.0
	# 颜料溅块：固定 seed，沿环分布的小色块（随 q 外扩、变淡）
	var R := Px.Rng.new(float(o.seed))
	for i in 7:
		var ang := R.range(0.0, TAU)
		var rad := R.range(8.0, 20.0)
		var life := R.range(0.55, 0.9)
		if q >= life:
			continue
		var u := q / life
		var x := cos(ang) * rad * (0.3 + 0.7 * u)
		var y := sin(ang) * rad * (0.3 + 0.7 * u)
		p.circle(x, y, maxf(0.7, 1.8 * (1.0 - u)), C[5] if i % 2 else C[4])
	# 扩散环（使用弹体色，白只保留在极早期）
	var rr := 3.0 + 24.0 * Px.Ease.outCubic(q)
	p.ring(0.0, 0.0, rr + 0.5, maxf(2.0, 3.5 * (1.0 - q)), WHITE if q < 0.18 else C[5], minf(1.0, (1.2 - q) * 1.8))
	p.glow(0.0, 0.0, 24.0 * (1.0 - q), int(C[4]), 0.5 * (1.0 - q))
