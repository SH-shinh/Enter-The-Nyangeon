# 参考 pixelfx `spawn/poof`（MIT）：命中处的小烟团。像素表现靠三件事——
# ① 只用 circle/ring/dot/px（走 put 的 4×4 Bayer 抖动，alpha 只有 0/1）；
# ② 6 帧 @30fps 的逐帧跳变（每帧半径差 ~2px，肉眼看得见"一格一格"）；
# ③ 三层错 1px 叠色（底影 C[3] / 主体 C[5] / 顶光 1px C[6]）+ 边缘毛糙团，
#    让灰烟在深浅地板上都有体积，而不是一块纯白饼。
# 运动：白核一闪 → 实心小团 → 中间开洞、外扩成环 → 上飘、变细、抖动消散。
# 由 script/bake_pixelfx_fx.gd 烘成 scenes/effects/bullet_smoke_frames.res（6 帧 / 48×48 / 0.2s）。
extends RefCounted

const Px := preload("res://addons/pixelfx/core/px.gd")
const WHITE := Px.WHITE

const D := 0.2

static var meta := {
	"name": "Bullet smoke",
	"desc": "A bullet hit kicks up a small pixel smoke ring: a white pop, a solid puff that opens in the middle, lumps round the rim, then a stepped dither dissolve as it drifts up.",
	"tags": ["impact", "hit", "smoke", "puff", "ring", "dust", "one-shot", "pixel"],
	"size": [48, 48],
	"origin": [24, 24],
	"duration": D,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#14131a", "#24222e", "#3b3846", "#5c5868", "#8b8699", "#bfbacc", "#eae7f2", "#ffffff"],
		"seed": 13,
	},
}


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	if t >= D:
		return
	var C := Px.fit(o.palette, 8)
	var Rp := Px.Rng.new(float(o.seed))
	var u := clampf(t / D, 0.0, 1.0)
	var e: float = Px.Ease.outCubic(u)
	# 后半段抖动淡出：put 在 a<1 时按 4×4 Bayer 直接抹像素 → 像素式消散
	var fade := 1.0 if u < 0.55 else 1.0 - (u - 0.55) / 0.45

	var cx := 0.0
	var cy := -3.0 * u                                     # 整体上飘
	var ring_r: float = 12.0 + 5.0 * e                     # 外半径 12 → 17（起手是实心大团）
	var ring_w: float = (12.0 - 6.0 * e) * (1.0 - 0.5 * Px.smooth(0.55, 1.0, u))

	# --- 主体三层：底影 → 主体 → 顶光（顶光只占外缘 1px） ---
	p.ring(cx, cy + 1.0, ring_r, ring_w, C[3], fade)
	p.ring(cx, cy, ring_r, ring_w, C[5], fade)
	p.ring(cx, cy - 1.0, ring_r - 0.4, 1.0, C[6], fade)

	# --- 边缘毛糙：10 团沿外圈铺开，半径位置各抖一点（固定 seed，逐帧布局一致） ---
	for i in 10:
		var ang: float = (float(i) / 10.0) * TAU + Rp.range(-0.22, 0.22)
		var bump := Rp.range(0.8, 1.15)
		var midr: float = ring_r - ring_w * 0.45 + Rp.range(-0.8, 0.8)
		var bx: float = cx + cos(ang) * midr
		var by: float = cy + sin(ang) * midr
		var br: float = ring_w * 0.42 * bump
		if br < 0.7:
			continue
		p.circle(bx, by + 1.0, br, C[3], fade)     # 团的下缘暗
		p.circle(bx, by, br, C[5], fade)           # 团主体（顶光由上面那圈统一给）

	# --- 白核 pop（前 ~2 帧）：实心，不抖动，避免中间出现棋盘噪点 ---
	var ck := 1.0 - u / 0.22
	if ck > 0.0:
		p.circle(cx, cy, 4.6 + 3.4 * ck, C[7])
		p.circle(cx, cy, 2.2 + 2.4 * ck, WHITE)

	# --- 外圈气浪：1px 硬环外扩后抖动消失（前 ~3 帧） ---
	var rk := Px.smooth(0.0, 0.5, u)
	if rk > 0.0 and rk < 1.0:
		p.ring(cx, cy, 8.0 + 10.0 * Px.Ease.outCubic(rk), 1.0, C[4], 1.0 - rk)
