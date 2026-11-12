extends RefCounted
## 中毒状态光环（俯视、无身体重绘、无地板元素）。
## 绿雾/毒汗/水泡的写法参考 pixelfx-godot `fx/status/poisoned.gd`（MIT,
## Copyright (c) 2026 Hugo Duprez / Sprite Fusion），按 ENN 改造成：
## - **不重绘身体**（不读 `o.actor` 的 silhouette、不画暗纹/不变色/不摇摆）；
## - **不画任何贴地元素**（去掉地面绿环与 sick glow），毒汗落到virtual脚底就消失；
## - 水泡与毒汗用固定点（身体中心为原点，24×36），每 0.8s 鼓一次。
## 运行时由 `scenes/debuff/status_aura.tscn` 的 AnimatedSprite2D 循环播放烘焙帧。

const Px := preload("res://addons/pixelfx/core/px.gd")
const Lib := preload("res://addons/pixelfx/fx/status/_lib.gd")
const WHITE := Px.WHITE

const DUR := 1.6
## 每 0.8s 鼓一次（参考库的 TICK）
const TICK := 0.8
## 毒汗下落的加速度与落点（虚拟脚底 y = +18）
const G := 420.0
const FLOOR_Y := 18.0

## 水泡：三处，交替鼓起
const BLISTERS := [
	[Vector2(-5.0, -4.0), Vector2(5.0, -8.0), Vector2(2.0, 6.0)],
	[Vector2(-7.0, -9.0), Vector2(6.0, -2.0), Vector2(-2.0, 7.0)],
]
## 毒汗：从头顶/肩侧渗出来
const SWEAT := [
	Vector2(-8.0, -12.0),
	Vector2(9.0, -10.0),
	Vector2(-9.0, 2.0),
	Vector2(8.0, 4.0),
]

static var meta := {
	"name": "Poison aura (top-down, bodyless)",
	"desc": "A body-less poisoned status: green vapour rolls up off a virtual 24x36 body, toxic sweat beads run and fall, blisters swell and pop every 0.8 s. No ground decal, no body repaint.",
	"tags": ["status", "poison", "toxic", "dot", "debuff", "loop"],
	"size": [80, 80],
	"origin": [40, 40],
	"duration": DUR,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": Px.PAL.poison,
		"veins": "#2c1a3a",
		"seed": 5,
	},
}


static func since(t: float) -> float:
	return fmod(fmod(t, TICK) + TICK, TICK)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var P: Array = Px.fit(o.palette, 8)
	var seed := float(o.seed)
	var ph := since(t)
	var tick := floori(t / TICK) % 2
	var breathe := 0.5 + 0.5 * sin(TAU * (t / DUR) * 2.0)
	# 核心辉光：对应燃烧"每个热点一个 p.glow"，毒是整团一个。两层让衰减更柔：
	# 外层铺开、内层亮核；亮度随 tick 呼吸（跳伤另有 modulate 脉冲）。
	p.glow(0.0, -5.0, 21.0 + 6.0 * breathe, P[6], 0.16 + 0.14 * breathe)
	p.glow(0.0, -5.0, 10.0 + 3.0 * breathe, P[7], 0.20 + 0.18 * breathe)
	# 绿雾：从身体表面往上滚；warm 给每团雾一个透光的内核（否则只是漫反射的糊）
	var vapour := Px.mix(P[3], P[5], 0.35)
	Px.cycle(t, DUR, 32, seed + 2.0, func(r: Px.Rng) -> float: return r.range(0.7, 1.1), func(age: float, life: float, r: Px.Rng, i: int) -> void:
		var base: Vector2 = SWEAT[i % SWEAT.size()]
		var x: float = base.x * 1.1 + sin(age * 3.0 + float(i)) * 3.0
		var y: float = base.y - 1.0 - Lib.travel(11.0, 6.0, 1.0, age)
		Lib.smoke(p, x, y, r.range(3.0, 4.6), age / life, vapour, 0.72, P[6]))
	# 发光孢子：雾里往上飘的亮点，对应燃烧的火星
	Px.cycle(t, DUR, 10, seed + 9.0, func(r: Px.Rng) -> float: return r.range(0.6, 1.0), func(age: float, life: float, r: Px.Rng, i: int) -> void:
		var base: Vector2 = SWEAT[i % SWEAT.size()]
		var x: float = base.x * 0.9 + sin(age * 5.0 + float(i)) * 2.0
		var y: float = base.y - 2.0 - Lib.travel(14.0, 8.0, 1.2, age)
		var u := age / life
		p.px(x, y, P[7] if u < 0.5 else P[6])
		p.glow(x, y, 3.0, P[5], 0.5 * (1.0 - u)))
	# 毒气体积：贴着身体的一层绿色薄膜（随 tick 呼吸），把"被毒气裹住"读出来。
	# 不是地面元素，也不是重绘身体——只是叠在身体前的一层低 alpha 雾。
	for i in 3:
		var yy := -12.0 + float(i) * 12.0
		p.disc(0.0, yy, 13.0 + 2.0 * breathe, P[4], 0.09 + 0.09 * breathe)
	# 水泡：鼓起 → 亮一下 → 破裂（只在 tick 前段）
	for bl: Vector2 in BLISTERS[tick]:
		var grow := Px.clamp(ph / 0.16, 0.0, 1.0)
		var pop := ph > 0.38
		if not pop:
			var r: float = (1.2 + 0.4 * float(tick)) * grow
			p.circle(bl.x, bl.y, r + 0.6, P[3])
			p.circle(bl.x - 0.2, bl.y - 0.2, r, P[5])
			if r > 0.8:
				p.px(bl.x - 0.5, bl.y - 0.8, WHITE)
			p.glow(bl.x, bl.y, 6.5, P[5], 0.45 * grow)
		elif ph < 0.56:
			var k := (ph - 0.38) / 0.18
			for j in 6:
				var an: float = (float(j) / 6.0) * TAU + bl.x
				var d: float = 2.0 + k * 3.5
				p.dot(bl.x + cos(an) * d, bl.y + sin(an) * d - k * 2.0, P[6] if j % 2 else P[5], 1.2 - k)
			p.glow(bl.x, bl.y, 8.0, P[6], 0.5 * (1.0 - k))
	# 毒汗：一点点渗出来，往下淌，掉到虚拟脚底就消失
	var per := DUR / 2.0
	for i in SWEAT.size():
		var sx: float = SWEAT[i].x
		var sy: float = SWEAT[i].y
		var age := fmod(fmod(t - float(i) * 0.37, per) + per, per)
		var gather := 0.35
		if age < gather:
			var k := age / gather
			var run := floorf(k * 2.0)
			p.px(sx, sy + run, P[6] if k > 0.5 else P[5])
			if k > 0.5:
				p.px(sx, sy + run - 1.0, P[4])
			continue
		var f := age - gather
		var drop_y := sy + 2.0 + 0.5 * G * f * f
		if drop_y < FLOOR_Y:
			p.line(sx, drop_y - minf(3.0, G * f * 0.012), sx, drop_y, P[4])
		else:
			# 落到虚拟脚底：只留一小撮消散的雾，不画地面痕迹
			var k2 := Px.clamp(1.0 - (drop_y - FLOOR_Y) / 6.0, 0.0, 1.0)
			if k2 > 0.0:
				p.dot(sx, FLOOR_Y - 1.0, P[5], 0.6 * k2)
				p.glow(sx, FLOOR_Y - 1.0, 4.0, P[5], 0.32 * k2)
