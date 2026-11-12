extends RefCounted
## 燃烧状态光环（俯视、无身体重绘、无地板元素）。
## 火舌/火星/薄烟取自 pixelfx-godot `fx/status/burning.gd` 的火焰配方（MIT,
## Copyright (c) 2026 Hugo Duprez / Sprite Fusion），按 ENN 改造成：
## - **不重绘身体**（不读 `o.actor` 的 silhouette，不闪白/不烤焦衣服）；
## - **不画任何贴地元素**（去掉了 floor flicker / 地面焦痕）；
## - 热点用固定虚拟身体坐标（身体中心为原点，24×36），四个点：头顶、右肩、左腰、右腰。
## 运行时由 `scenes/debuff/status_aura.tscn` 的 AnimatedSprite2D 循环播放烘焙帧。

const Px := preload("res://addons/pixelfx/core/px.gd")
const Lib := preload("res://addons/pixelfx/fx/status/_lib.gd")

const DUR := 1.2
## 每 0.6s 窜一下（参考库的 TICK），与 DOT 跳伤无强绑定，跳到伤害时另用 modulate 脉冲
const TICK := 0.6
const WIND := -14.0
## 虚拟身体上的六个热点（相对身体中心）
const SPOTS := [
	Vector2(-7.0, -14.0),
	Vector2(6.0, -15.0),
	Vector2(-9.0, -4.0),
	Vector2(9.0, -3.0),
	Vector2(-6.0, 6.0),
	Vector2(6.0, 7.0),
]

static var meta := {
	"name": "Burning aura (top-down, bodyless)",
	"desc": "A body-less burning status: small flame tongues lick from four hot spots on a virtual 24x36 body, trailing sparks and thin smoke; they flare every 0.6 s. No ground decal, no body repaint.",
	"tags": ["status", "fire", "burn", "dot", "debuff", "loop"],
	"size": [80, 80],
	"origin": [40, 40],
	"duration": DUR,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": Px.PAL.fire,
		"smoke": "#5b5566",
		"seed": 3,
	},
}


static func since(t: float) -> float:
	return fmod(fmod(t, TICK) + TICK, TICK)


static func flare(t: float) -> float:
	return exp(-since(t) / 0.12)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F: Array = Px.fit(o.palette, 9)
	F.reverse()
	var fl := flare(t)
	var flick := 0.8 + 0.2 * Lib.tnoise(t, DUR, 7.5, 3)
	var seed := float(o.seed)
	# 薄烟：从每个热点向上飘，越飘越淡
	var smoke_c := Px.mix(Px.hex(o.smoke), F[6], 0.2)
	Px.cycle(t, DUR, 16, seed + 4.0, func(r: Px.Rng) -> float: return r.range(0.8, 1.2), func(age: float, life: float, r: Px.Rng, i: int) -> void:
		var sp: Vector2 = SPOTS[i % SPOTS.size()]
		var x: float = sp.x + Lib.travel(WIND * 0.6, WIND * 0.5, 0.8, age) + sin(age * 4.0 + float(i)) * 1.2
		var y: float = sp.y - 3.0 - Lib.travel(18.0, 6.0, 1.0, age)
		Lib.smoke(p, x, y, r.range(1.1, 1.9), age / life, smoke_c, 0.9))
	# 火舌：每个热点 3 条，窜的时候变高变亮
	for i in SPOTS.size():
		var sp: Vector2 = SPOTS[i]
		var base_h := 6.2 if i < 2 else 4.8
		for j in 3:
			var dx: float = (float(j) - 1.0) * 1.6
			var n: float = float(i * 17 + j * 5) + seed
			var h: float = base_h * (0.85 + 0.25 * Lib.tnoise(t, DUR, 5.0, n)) * (1.0 + 1.6 * fl)
			var sx: float = WIND * 0.08 * h / 4.0 + Lib.tnoise(t, DUR, 3.0, n + 9.0) * 0.8
			Lib.tongue(p, sp.x + dx, sp.y, h, 1.3 + 0.4 * fl, sx, F, t, DUR, n)
		p.glow(sp.x, sp.y - 2.0, (13.0 + 8.0 * fl) * flick, F[4], 0.26 + 0.38 * fl)
	# 火星：从热点往上、往外飘
	Px.cycle(t, DUR, 20, seed + 6.0, func(r: Px.Rng) -> float: return r.range(0.5, 0.9), func(age: float, life: float, r: Px.Rng, i: int) -> void:
		var sp: Vector2 = SPOTS[i % SPOTS.size()]
		var x: float = sp.x + r.range(-1.5, 1.5) + Lib.travel(WIND + r.range(-10.0, 6.0), WIND * 0.6, 1.2, age) + sin(age * 9.0 + float(i)) * 1.2 * age
		var y: float = sp.y - 2.0 + Lib.travel(-r.range(25.0, 55.0), -18.0, 1.4, age)
		Lib.ember(p, x, y, age / life, [F[1], F[3], F[5]], age + float(i)))
