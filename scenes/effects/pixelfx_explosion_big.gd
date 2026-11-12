extends "res://addons/pixelfx/core/effect.gd"
## 大爆炸（俯视）：粒子语汇照 `fx/explosions/big-explosion.gd` 重写。
## 与参考库的取舍（俯视 / 224 画布 / 0.85s）：
## - **搬**：`Lib.fireBall`（每个火团画成有火芯/边缘/高光/辉光的体积球，`drawPs` 自动套用）、
##   `Lib.rock` + `Lib.trail`（碎石带火星拖尾）、`Px.flare` 英雄帧、`Lib.fireRamp`/`stone` 色阶；
## - **不搬**：`Plume`/`Column`（蘑菇柱）、`dome`（半球贴地）、`pool`/`crater`（地面）——都是侧视专用；
## - 地板只保留正圆焦痕（用户明确：不加燃烧地火与尘环）。
## 运行时仍是 AnimatedSprite2D 播烘焙帧（`scenes/effects/explosion_big_frames.res`）。

const Px := preload("res://addons/pixelfx/core/px.gd")
const Lib := preload("res://scenes/effects/pixelfx_explosion_lib.gd")
const RxLib := preload("res://addons/pixelfx/fx/explosions/_lib.gd")

const DUR := 0.85
## 只比小爆炸（34）大一圈：环半径 42×1.35 = 57 vs 46 ≈ 1.24×
const RAD := 42.0
## 二次冲击环/补闪的起跳时刻（相对 create）
const AFTERSHOCK_AT := 0.17
const SECOND_FLASH_AT := 0.20
## 与参考库同一条烟色阶（亮→暗），供 lobe / trail 用
const SMOKE_RAMP := ["#83777f", "#6e6470", "#575060", "#3f3947", "#29242f"]
## 参考库的石头色
const STONE_HEX := "#5a4a38"
## 拖尾寿命（秒）与单块最多保留的点数
const TRAIL_LIFE := 0.45
const TRAIL_MAX := 8

static var meta := {
	"name": "Explosion (big, top-down)",
	"desc": "A heavy ground blast centred on the hit point: white flash and a flare, a wide shock ring, a second ring and flash as the fireball collapses, a mass of shaded fire balls, a thick smoke bloom, a burst of yellow-orange sparks and embers, and burning stone chips thrown in arcs that land and smoulder.",
	"tags": ["explosion", "fire", "smoke", "impact", "big", "one-shot"],
	"size": [224, 224],
	"origin": [112, 112],
	"duration": DUR,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Px.PAL.fire, "seed": 11},
}

var F: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var flashes: Array = []
var rings: Array = []
var chunks: Array = []
## 火色阶（亮→暗）与暖色阶：`fireBall` / `rock` / `trail` 只认这个，不认 palette
var FR: Array = []
var SM: Array = []
var st: Dictionary = {}
## 厚烟团：用 `Lib.lobe` 画的几个体积块（参考库的蘑菇柱是侧视的，这里只取"厚"）
var _smoke_lobes: Array = []
## 与 chunks 同下标的轨迹点（{x, y, t}），给 `Lib.trail` 用
var _trails: Array = []
var t := 0.0
var _shock_done := false
var _flash2_done := false


func create(o: Dictionary) -> void:
	F = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "sparks": [F[7], F[6], F[5], F[4]]})
	lights = Px.Lights.new()
	FR = RxLib.fireRamp(F)
	SM = Px.ramp(SMOKE_RAMP)
	st = RxLib.stone(STONE_HEX)
	var made: Dictionary = Lib.spawn_blast(R, ps, lights, F, {
		"rad": RAD, "dur": DUR, "power": 0.95, "half": 112.0, "ring_thick": 4.0,
		# 火团数量按参考库收紧、尺寸按参考库放大（单个火团现在是有体积的球，堆多了会糊）
		"fire_core": 14, "fire_out": 26, "fire_wave2": 8, "smoke": 12,
		"fire_core_size": Vector2(RAD * 0.40, RAD * 0.55),
		"fire_out_size": Vector2(RAD * 0.22, RAD * 0.46),
		# nuke 密度的橙黄粒子：速度×寿命 ≤ 100px（不越 224 画布）
		"sparks": 80, "spark_sp": Vector2(130.0, 220.0), "spark_life": Vector2(0.26, 0.34), "spark_r": 0.55,
		"embers": 40, "ember_sp": Vector2(70.0, 150.0),
		# 抛物线碎片：平飞 ≤77px、抛高 ≤22px、滞空 0.27–0.44s
		"chunks": 14, "chunk_sp": Vector2(90.0, 170.0), "chunk_vz": Vector2(120.0, 200.0),
		"chunk_len": Vector2(5.0, 10.0),
	})
	flashes = made["flashes"]
	rings = made["rings"]
	chunks = made["chunks"]
	# 厚烟团：4 个深色体积块，0.18s 后陆续出现，往外滚（太早会抢火球的亮度）
	_smoke_lobes.clear()
	for i in 4:
		var a := R.range(0.0, TAU)
		var d := R.range(RAD * 0.15, RAD * 0.45)
		_smoke_lobes.append({
			"x": cos(a) * d, "y": sin(a) * d,
			"vx": cos(a) * R.range(6.0, 14.0), "vy": sin(a) * R.range(6.0, 14.0),
			"r0": R.range(9.0, 14.0), "grow": R.range(20.0, 30.0),
			"z": R.range(-0.5, 0.5), "dark": 1, "delay": R.range(0.18, 0.28),
		})
	# 轨迹点：每块一条
	_trails.clear()
	for i in chunks.size():
		_trails.append([])


func update(dt: float) -> void:
	t += dt
	if not _shock_done and t >= AFTERSHOCK_AT:
		_shock_done = true
		rings.append({"r0": RAD * 0.35, "r1": RAD * 1.6, "life": DUR * 0.34, "max": DUR * 0.34, "thick": 2.6, "c": F[4]})
	if not _flash2_done and t >= SECOND_FLASH_AT:
		_flash2_done = true
		flashes.append({"r": RAD * 0.7, "life": DUR * 0.12, "max": DUR * 0.12})
		lights.add(0.0, 0.0, RAD * 2.0, Lib.WARM, 0.4, DUR * 0.3)
	Lib.tick_timers(flashes, dt)
	Lib.tick_timers(rings, dt)
	Lib.tick_chunks(dt, chunks, ps, F)
	ps.update(dt)
	lights.update(dt)
	for L: Dictionary in _smoke_lobes:
		L["x"] = float(L["x"]) + float(L["vx"]) * dt
		L["y"] = float(L["y"]) + float(L["vy"]) * dt
	# 记录碎片轨迹（绘制点同样是 y − z）
	for i in chunks.size():
		var b: Dictionary = chunks[i]
		var pts: Array = _trails[i]
		pts.append({"x": float(b["x"]), "y": float(b["y"]) - float(b["z"]), "t": t})
		while pts.size() > TRAIL_MAX:
			pts.pop_front()
		while not pts.is_empty() and t - float(pts[0]["t"]) > TRAIL_LIFE:
			pts.pop_front()


func drawBack(p: Px.Painter) -> void:
	Lib.scorch(p, F, t, DUR, RAD * 0.95, DUR * 0.78)
	RxLib.drawPs(p, ps, "back", FR)


func draw(p: Px.Painter) -> void:
	# 厚烟团压在最下面（烟在火球后面/中间）
	var fade := 1.0 - Px.smooth(DUR * 0.55, DUR * 0.92, t)
	for L: Dictionary in _smoke_lobes:
		if t < float(L["delay"]) or fade <= 0.0:
			continue
		var r: float = float(L["r0"]) + float(L["grow"]) * t
		RxLib.lobe(p, float(L["x"]), float(L["y"]), minf(r, 96.0), FR, SM, 0.0, 0.0, 0.45 * fade, float(L["z"]), int(L["dark"]), 1)
	# 中心火核：参考库靠 dome + plume 撑住"一团亮球"，这里用一个高 fire 的 lobe 顶上
	if t < DUR * 0.78:
		var u := clampf(t / (DUR * 0.78), 0.0, 1.0)
		var fire := 0.95 * (1.0 - pow(u, 1.6))
		RxLib.lobe(p, 0.0, 0.0, minf(RAD * 0.45 + 22.0 * t, 84.0), FR, SM, fire, fire * 0.6, 1.0 - u * 0.45, 0.25, 0, 1)
	# 火团 / 烟 / 火花 / 余烬：drawPs 会把每个 FIRE 画成体积火球（参考库的 fireBall）
	RxLib.drawPs(p, ps, "front", FR)
	_draw_chunks(p)
	# 英雄帧：只在开头 0.24s，给"炸开"那一下
	if t < 0.24:
		var k := 1.0 - t / 0.24
		Px.flare(p, 0.0, 0.0, 70.0 * pow(k, 1.4), k, F)
	Lib.draw_flashes(p, flashes, F)
	Lib.draw_rings(p, rings, F)
	lights.draw(p)


## 碎片：先画火星拖尾再画石块本体（同参考库 draw 里 trail → rock 的顺序）
func _draw_chunks(p: Px.Painter) -> void:
	var life_left := maxf(0.0, DUR - t)
	if life_left <= 0.0:
		return
	for i in chunks.size():
		var b: Dictionary = chunks[i]
		var pts: Array = _trails[i]
		if pts.size() >= 2:
			RxLib.trail(p, pts, t, FR, SM, TRAIL_LIFE, 0.6 + float(b["s"]) * 0.3, float(b["heat"]))
		RxLib.rock(p, {
			"x": float(b["x"]), "y": float(b["y"]) - float(b["z"]),
			"s": float(b["s"]) * 0.55, "a": float(b["a"]), "heat": float(b["heat"]), "life": life_left,
		}, st, FR)
