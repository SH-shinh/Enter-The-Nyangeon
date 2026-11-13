# 参考 pixelfx scifi/scanner（MIT）：无 actor 化的锁定入场 —— 括号收拢 + 扫描一次 + 发白。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")

static var meta := {
	"name": "Hare lock in",
	"desc": "Brackets snap inward, a scan line sweeps once and the frame flashes white.",
	"tags": ["scifi", "scan", "lock", "target", "one-shot"],
	"size": [64, 64],
	"origin": [32, 32],
	"duration": 0.6,
	"loop": false,
	"fps": 45,
	"bg": "ground",
	"options": {
		"palette": ["#0a1400", "#1c2e00", "#3f5c00", "#6f8f00", "#a8c400", "#d6f04a", "#f2ffb0", "#ffffff"],
		"seed": 22,
	},
}

const D := 0.6
const B := 16.0
const ARM := 6.0


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	if t >= D:
		return
	var C := Px.fit(o.palette, 8)
	var snap := Px.Ease.inOutSine(Px.clamp(t / 0.18))
	var b: float = B * Px.lerp(1.8, 1.0, snap)
	var white := Px.clamp((t - 0.40) / 0.14)
	var fade := 1.0 - Px.clamp((t - 0.52) / 0.08) * 0.65
	var line_col: int = Px.mix(C[6], C[7], white)
	var soft_col: int = Px.mix(C[4], C[6], white)
	var pulse := (0.75 + 0.25 * sin(t * TAU / 0.18)) * fade

	# 括号：入场时快速收拢，末段发白
	for sx: float in [-1.0, 1.0]:
		for sy2: float in [-1.0, 1.0]:
			var x: float = sx * b
			var y: float = sy2 * b
			p.line(x, y, x - sx * ARM, y, line_col, 0.95 * pulse)
			p.line(x, y + sy2, x - sx * ARM, y + sy2, soft_col, 0.8 * pulse)
			p.line(x, y, x, y - sy2 * ARM, line_col, 0.95 * pulse)
			p.line(x + sx, y, x + sx, y - sy2 * ARM, soft_col, 0.8 * pulse)
			p.dot(x, y, C[7], pulse)
			p.glow(x, y, 5.0, soft_col, 0.30 * pulse)

	# 扫描线：只扫一次
	if t >= 0.10 and t <= 0.42:
		var st := Px.clamp((t - 0.10) / 0.32)
		var sy3: float = Px.lerp(-b, b, Px.Ease.inOutSine(st))
		p.line(-b, sy3, b, sy3, C[7], 0.95)
		p.line(-b, sy3 + 1.0, b, sy3 + 1.0, C[6], 0.8)
		p.line(-b, sy3 - 1.0, b, sy3 - 1.0, C[5], 0.5)
		p.glow(0.0, sy3, 14.0, soft_col, 0.45)
		p.dot(-b, sy3, C[7], 1.0)
		p.dot(b, sy3, C[7], 1.0)

	# 发白中心光：末段整框过曝一下
	if white > 0.0:
		p.glow(0.0, 0.0, 16.0, C[7], 0.35 * white)
