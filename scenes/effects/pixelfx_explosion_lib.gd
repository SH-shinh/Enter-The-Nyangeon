extends RefCounted
## 俯视版爆炸的共用件。
## 结构参考 pixelfx-godot `fx/explosions/small-explosion.gd`（MIT, Copyright (c) 2026 Hugo Duprez /
## Sprite Fusion 的 explosion 配方），按本项目改成：640×360 俯视、0.5–0.9s 战斗级节奏、
## 正圆地面环与焦痕、无侧视地面线（去掉依赖地平面的 blaze/抛物线弹道）。
##
## 只放"两种尺寸共用"的东西：爆炸生成、焦痕、闪光/冲击环绘制。

const Px := preload("res://addons/pixelfx/core/px.gd")
const P := Px.P
const PF := Px.PF

const WARM := "#ffb060"
const WHITE_HEX := "#ffffff"
## 石屑的明暗梯度（俯视看不出"受光面"，用亮边/暗边制造体积）。
const STONE_RAMP := ["#1c1610", "#33281c", "#4f3f2c", "#6e5a40", "#927a58", "#b89f78", "#dcc8a2"]
## 横截面四行：外缘描黑 / 背光暗 / 受光亮 / 拖尾侧发热
const CHUNK_OFFSETS := [-1.0, -0.4, 0.4, 1.0]

# 颜色只在首次用到时转换一次（原来每次 draw 都 Px.hex / Px.ramp 一遍）
static var C_OUTLINE := Px.hex("#1a1422")
static var C_SHADOW := Px.hex("#120c14")
static var C_SOOT := Px.hex("#0d0a12")
static var C_SOOT2 := Px.hex("#17121d")
static var C_STONE: Array = Px.ramp(STONE_RAMP)


## 一次爆炸的全部粒子/碎片/光。cfg: rad, dur, power, fire_core, fire_out, fire_wave2, smoke,
## sparks/embers 的速度与寿命、chunks（数量/速度/抛高/长度）。返回 {flashes, rings, chunks}。
static func spawn_blast(R: Px.Rng, ps: Px.Particles, lights: Px.Lights, F: Array, cfg: Dictionary) -> Dictionary:
	var rad: float = float(cfg["rad"])
	var dur: float = float(cfg["dur"])
	var power: float = float(cfg.get("power", 0.6))
	var thick: float = float(cfg.get("ring_thick", 3.0))
	var flashes: Array = []
	var rings: Array = []

	flashes.append({"r": rad * 1.1, "life": dur * 0.20, "max": dur * 0.20})
	rings.append({"r0": rad * 0.4, "r1": rad * 1.35, "life": dur * 0.34, "max": dur * 0.34, "thick": thick, "c": F[5]})
	rings.append({"r0": rad * 0.25, "r1": rad * 0.95, "life": dur * 0.20, "max": dur * 0.20, "thick": maxf(1.2, thick * 0.55), "c": F[3]})

	# 最外层暖光必须收在画布内（边缘 8px 会被 Baker.edge_fade 吃掉，越界会露出方框光）
	var half: float = float(cfg.get("half", rad * 2.4))
	lights.add(0.0, 0.0, minf(rad * 3.2, half - 14.0), WARM, 0.75 * power, dur * 0.75)
	lights.add(0.0, 0.0, rad * 1.5, WHITE_HEX, 0.5, dur * 0.16)

	# 核心火球：原地翻滚，冷却成烟
	# 尺寸可被 cfg 覆盖（参考库大爆炸用 rad*0.40–0.55，本项目的紧凑档用默认值）
	var core_sz: Vector2 = cfg.get("fire_core_size", Vector2(rad * 0.28, rad * 0.44))
	var i := 0
	while i < int(cfg.get("fire_core", 6)):
		ps.spawn(P.FIRE, R.range(-rad * 0.1, rad * 0.1), R.range(-rad * 0.1, rad * 0.1), R.range(-18.0, 18.0), R.range(-18.0, 18.0),
			R.range(dur * 0.55, dur * 0.85), 0, R.range(core_sz.x, core_sz.y))
		i += 1

	# 向外喷的火团：一半在熄灭时转烟
	var out_sz: Vector2 = cfg.get("fire_out_size", Vector2(rad * 0.18, rad * 0.36))
	i = 0
	while i < int(cfg.get("fire_out", 18)):
		var a: float = R.range(0.0, TAU)
		var d: float = R.range(0.0, rad * 0.22)
		var sp: float = R.range(70.0, 200.0) * (0.55 + power)
		ps.spawn(P.FIRE, cos(a) * d, sin(a) * d, cos(a) * sp, sin(a) * sp,
			R.range(dur * 0.38, dur * 0.72), 0, R.range(out_sz.x, out_sz.y), 0.0,
			(PF.SMOKES | PF.BIG) if R.chance(0.45) else 0)
		i += 1

	# 第二波：延迟补喷，让火在爆炸中段还活着（参考库靠长时长撑住，这里靠补喷）
	i = 0
	while i < int(cfg.get("fire_wave2", 8)):
		var aw: float = R.range(0.0, TAU)
		var dw: float = R.range(rad * 0.1, rad * 0.42)
		var spw: float = R.range(30.0, 90.0)
		ps.spawn(P.FIRE, cos(aw) * dw, sin(aw) * dw, cos(aw) * spw, sin(aw) * spw,
			R.range(dur * 0.35, dur * 0.60), 0, R.range(rad * 0.16, rad * 0.32),
			R.range(dur * 0.18, dur * 0.38), PF.SMOKES if R.chance(0.6) else 0)
		i += 1

	# 烟团：火先烧起来再冒烟，向外滚并上浮（俯视里"上浮"就是远离中心的漂移）。
	# 颜色传 F[2]：P.SMOKE 会按年龄把火色混向烟色，形成"火冷却成烟"。
	i = 0
	while i < int(cfg.get("smoke", 10)):
		var a2: float = R.range(0.0, TAU)
		var d2: float = R.range(rad * 0.08, rad * 0.4)
		ps.spawn(P.SMOKE, cos(a2) * d2, sin(a2) * d2, cos(a2) * 30.0, sin(a2) * 30.0 - 10.0,
			R.range(dur * 0.45, dur * 0.85), F[3], R.range(rad * 0.3, rad * 0.5),
			R.range(dur * 0.25, dur * 0.50), PF.BIG)
		i += 1

	# 火花：拖尾短线，从火球外缘起飞（起点给半径，否则早期全被火球盖住）。
	# 速度×寿命 + 半径必须 < 画布半宽−10，否则 bbox 断言会失败。
	var spark_sp: Vector2 = cfg.get("spark_sp", Vector2(140.0, 300.0))
	var spark_life: Vector2 = cfg.get("spark_life", Vector2(0.10, 0.20))
	var spark_r: float = float(cfg.get("spark_r", 0.0)) * rad
	i = 0
	while i < int(cfg.get("sparks", 34)):
		var a3: float = R.range(0.0, TAU)
		var sp3: float = R.range(spark_sp.x, spark_sp.y)
		ps.spawn(P.SPARK, cos(a3) * spark_r, sin(a3) * spark_r, cos(a3) * sp3, sin(a3) * sp3,
			R.range(spark_life.x, spark_life.y))
		i += 1

	# 余烬：慢慢飘散的亮点
	var ember_sp: Vector2 = cfg.get("ember_sp", Vector2(50.0, 110.0))
	i = 0
	while i < int(cfg.get("embers", 14)):
		var a4: float = R.range(0.0, TAU)
		var sp4: float = R.range(ember_sp.x, ember_sp.y)
		ps.spawn(P.EMBER, cos(a4) * rad * 0.2, sin(a4) * rad * 0.2, cos(a4) * sp4, sin(a4) * sp4,
			R.range(dur * 0.45, dur * 0.85), F[3])
		i += 1

	# 抛物线燃烧碎片（假 Z：平面 x/y + 高度 z，绘制在 y − z），参考 barrel-explosion 的 staves。
	# 俯视没有真实重力方向，所以"抛出 → 落下 → 弹一下 → 静止"用 z 轴模拟；
	# 空间配比：平飞 ≤ 画布半宽−10，抛高 ≤ 22，两者相加也不能越界。
	var chunks: Array = []
	var chunk_sp: Vector2 = cfg.get("chunk_sp", Vector2(80.0, 150.0))
	var chunk_vz: Vector2 = cfg.get("chunk_vz", Vector2(120.0, 200.0))
	var chunk_len: Vector2 = cfg.get("chunk_len", Vector2(3.0, 6.0))
	i = 0
	while i < int(cfg.get("chunks", 9)):
		var a5: float = R.range(0.0, TAU)
		var sp5: float = R.range(chunk_sp.x, chunk_sp.y)
		chunks.append({
			"x": cos(a5) * rad * 0.16, "y": sin(a5) * rad * 0.16,
			"z": R.range(1.0, 6.0), "vx": cos(a5) * sp5, "vy": sin(a5) * sp5,
			"vz": R.range(chunk_vz.x, chunk_vz.y), "a": R.range(0.0, TAU),
			"va": R.range(-10.0, 10.0), "s": R.range(chunk_len.x, chunk_len.y),
			"heat": R.range(0.65, 1.0), "rest": false, "warm": false,
		})
		i += 1

	return {"flashes": flashes, "rings": rings, "chunks": chunks}


## 地面焦痕：正圆（参考库是夹在地面线上的 3 行横条，侧视专用）。
static func scorch(p: Px.Painter, F: Array, t: float, dur: float, r0: float, cool: float) -> void:
	var fade := 1.0 - Px.smooth(dur * 0.62, dur, t)
	if fade <= 0.0:
		return
	var rr := r0 * minf(1.0, t / maxf(0.001, dur * 0.12))
	if rr < 1.0:
		return
	var heat: Array = F.duplicate()
	heat.reverse()
	var soot: int = C_SOOT
	var soot2: int = C_SOOT2
	var r := int(ceil(rr))
	var cool_k := Px.clamp(1.0 - t / maxf(0.001, cool), 0.0, 1.0)
	p.shade(-float(r), -float(r), float(r), float(r), func(x: float, y: float, out) -> void:
		var d := Px.hypot(x, y) / rr
		if d > 1.0:
			return
		var jitter := Px.rand(int(x) * 31 + int(y), 3)
		var heatk := pow(cool_k, 1.4) * (1.25 - d) - jitter * 0.35
		if heatk > 0.06:
			var idx := mini(heat.size() - 1, int(floorf((1.0 - minf(1.0, heatk)) * float(heat.size() - 1))))
			out.c = heat[idx]
			out.a = fade
		else:
			out.c = soot if d < 0.5 else soot2
			out.a = (1.0 if d < 0.95 - jitter * 0.3 else 1.0 - d) * fade)


static func draw_flashes(p: Px.Painter, flashes: Array, F: Array) -> void:
	for f: Dictionary in flashes:
		var k: float = float(f["life"]) / float(f["max"])
		var r: float = float(f["r"]) * (0.8 + 0.2 * k)
		p.circle(0.0, 0.0, r + 1.4, F[2])
		p.circle(0.0, 0.0, r, F[6] if k > 0.45 else F[5])
		p.circle(0.0, 0.0, r * 0.6, Px.WHITE if k > 0.45 else F[6])


static func draw_rings(p: Px.Painter, rings: Array, F: Array) -> void:
	for q: Dictionary in rings:
		var k: float = float(q["life"]) / float(q["max"])
		var e := 1.0 - pow(k, 3.0)
		var r: float = float(q["r0"]) + (float(q["r1"]) - float(q["r0"])) * e
		var th := maxf(1.5, float(q["thick"]) * k + 0.6)
		# Px.band：外沿带白热边、向内渐暗的环，比 p.ring 的平涂更像冲击波
		Px.band(p, 0.0, 0.0, r, 1.0, th, minf(1.0, k * k * 2.2), F.slice(2), null, k > 0.75)


static func tick_timers(list: Array, dt: float) -> void:
	var i := list.size() - 1
	while i >= 0:
		var q: Dictionary = list[i]
		q["life"] = float(q["life"]) - dt
		if float(q["life"]) <= 0.0:
			list.remove_at(i)
		i -= 1


## 抛物线碎片：一条会翻滚的短石条（参考 barrel-explosion 的 staves 俯视化）。
## 绘制点 = (x, y − z)，地面上再补一个随高度变淡的影子，把"抛起来"读出来。
static func draw_chunks(p: Px.Painter, list: Array, F: Array, fade: float) -> void:
	if list.is_empty() or fade <= 0.0:
		return
	var st: Array = C_STONE
	var outline: int = C_OUTLINE
	var shadow: int = C_SHADOW
	var lit: int = st[6]
	var body: int = st[4]
	var dark: int = st[2]
	var hot: int = F[4]
	# 横截面四行：外缘描黑 / 背光暗 / 受光亮 / 拖尾侧发热（冷却后回黑）
	var offsets: Array = CHUNK_OFFSETS
	for b: Dictionary in list:
		var ca := cos(float(b["a"]))
		var sa := sin(float(b["a"]))
		var length := float(b["s"])
		var heat := float(b["heat"])
		var z := float(b["z"])
		var gx := float(b["x"])
		var gy := float(b["y"])
		var y := gy - z
		if z > 0.5:
			p.dot(gx, gy, shadow, 0.32 * clampf(1.0 - z / 40.0, 0.15, 1.0) * fade)
		# 刚炸出去的几帧整块偏火色，冷却后回到石色 —— 这是"燃烧碎块"的读数关键
		var face: int = lit
		if heat > 0.7:
			face = F[6]
		elif heat > 0.45:
			face = F[5]
		elif heat > 0.2:
			face = F[4]
		var glow_a := minf(1.0, heat * 1.6)
		var d := 0.0
		while d <= length:
			var u := d - length * 0.5
			var x := gx + ca * u
			var yy := y + sa * u
			var nx := sa
			var ny := -ca
			p.dot(x + nx * offsets[0], yy + ny * offsets[0], outline, fade)
			p.dot(x + nx * offsets[1], yy + ny * offsets[1], dark if heat <= 0.25 else body, fade)
			p.dot(x + nx * offsets[2], yy + ny * offsets[2], face, fade)
			if heat > 0.25:
				p.dot(x + nx * offsets[3], yy + ny * offsets[3], hot, fade * glow_a)
			else:
				p.dot(x + nx * offsets[3], yy + ny * offsets[3], outline, fade)
			d += 0.5
		if heat > 0.45:
			p.glow(gx, y, 4.0 + length * 0.6, hot, 0.35 * heat * fade)


## 碎片的假 Z 积分：平面阻力 + 重力；落地弹一次后静止，热量降到 0.3 时原地补火星。
static func tick_chunks(dt: float, list: Array, ps: Px.Particles, F: Array) -> void:
	# 全部静止且已经凉透就不用再跑了
	var alive := false
	for b: Dictionary in list:
		if not bool(b["rest"]) or float(b["heat"]) > 0.0:
			alive = true
			break
	if not alive:
		return
	for b: Dictionary in list:
		if not bool(b["rest"]):
			var vx := float(b["vx"]) - float(b["vx"]) * 2.2 * dt
			var vy := float(b["vy"]) - float(b["vy"]) * 2.2 * dt
			b["vx"] = vx
			b["vy"] = vy
			b["x"] = float(b["x"]) + vx * dt
			b["y"] = float(b["y"]) + vy * dt
			var vz := float(b["vz"]) - 900.0 * dt
			b["vz"] = vz
			b["z"] = float(b["z"]) + vz * dt
			b["a"] = float(b["a"]) + float(b["va"]) * dt
			if float(b["z"]) <= 0.0:
				b["z"] = 0.0
				if vz < -70.0:
					b["vz"] = -vz * 0.35
					b["vx"] = vx * 0.6
					b["vy"] = vy * 0.6
					b["va"] = float(b["va"]) * 0.6
				else:
					b["rest"] = true
					b["vx"] = 0.0
					b["vy"] = 0.0
					b["vz"] = 0.0
		var heat := maxf(0.0, float(b["heat"]) - 0.9 * dt)
		b["heat"] = heat
		if heat < 0.3 and not bool(b["warm"]):
			b["warm"] = true
			for i in 2:
				ps.spawn(P.EMBER, float(b["x"]), float(b["y"]), 0.0, -10.0, 0.26, F[3])
