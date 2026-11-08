extends Node2D
## 感电单链电弧：运行时按参考库 lightning/chain-lightning 的笔触绘制。
## 形状/描边思路参考 pixelfx-godot addons/pixelfx/fx/lightning/{_lib.gd,chain-lightning.gd}
## （bolt shape / inking adapted from Sprite Fusion's lightning, MIT, Hugo Duprez）。
##
## 不烘焙：链是任意长度/角度的动态连线，固定画布贴图会拉伸像素；本脚本只画几十条折线，
## 开销远低于整画布 pixelfx LIVE（见 docs/REFERENCE_PIXELFX.md）。
##
## 池契约：is_idle / idle_state() / PoolManager.add_pool("shock_chain", self)
## 接口：play(points: Array, power: int)

const POOL_ID := "shock_chain"

# ---- 调色（蓝紫，与 DamageData.COLOR_SHOCK #7B8CFF 同源） ----
const HALO := Color(0.10, 0.08, 0.32, 0.65)
const BODY := Color(0.30, 0.34, 1.0)
const CORE := Color(0.86, 0.85, 1.0)
const SPARK := Color(0.70, 0.62, 1.0)
const WHITE := Color(1, 1, 1, 1)

# ---- 时序 ----
const WIND := 0.02
const LEAP := 0.03
const HOLD := 0.10
const FADE := 0.06
const FLASH := 0.12
const REDRAW := 0.033

# ---- 形状 ----
const JAG := 0.22
const FORKS := 0.35
const MIN_FORK_LEN := 24.0

# ---- 音效 ----
const SFX_MIN_MS := 90

const GLOW_TEX := preload("res://sprites/particle/circular_1.png")

var is_idle: int = 1

var _points: Array[Vector2] = []
var _paths: Array = []
var _nodes: Array = []
var _power: int = 1
var _age: float = 0.0
var _redraw_accum: float = 0.0
var _play_id: int = 0
var _rng := RandomNumberGenerator.new()

@onready var _sfx: AudioStreamPlayer = $Sfx

static var _last_sfx_ms: int = -1000000


func _ready() -> void:
	PoolManager.add_pool(POOL_ID, self)
	visible = false
	set_process(false)


func idle_state() -> void:
	reset_physics_interpolation()
	is_idle = 1
	visible = false
	modulate.a = 1.0
	_points.clear()
	_paths.clear()
	_nodes.clear()
	_age = 0.0
	_redraw_accum = 0.0
	set_process(false)
	queue_redraw()


func play(points: Array, power: int) -> void:
	if points.size() < 2:
		return
	reset_physics_interpolation()
	global_position = Vector2.ZERO
	is_idle = 0
	visible = true
	modulate.a = 1.0
	_power = clampi(power, 1, 6)
	_age = 0.0
	_redraw_accum = REDRAW
	_play_id = (Time.get_ticks_msec() + int(get_instance_id())) & 0x7fffffff
	_points.clear()
	for p in points:
		_points.append(to_local(p))
	_nodes.clear()
	for i in _points.size():
		_nodes.append({
			"flash_at": WIND + float(i) * LEAP,
			"sparks": _make_sparks(i),
		})
	_rebuild()
	set_process(true)
	queue_redraw()
	_play_sfx()


func _process(delta: float) -> void:
	_age += delta
	_redraw_accum += delta
	var hold_end := _hold_end()
	if _redraw_accum >= REDRAW and _age < hold_end:
		_redraw_accum = 0.0
		_rebuild()
		queue_redraw()
	if _age > hold_end:
		modulate.a = clampf((_life() - _age) / FADE, 0.0, 1.0)
	if _age >= _life():
		idle_state()


func _life() -> float:
	return _hold_end() + FADE


func _hold_end() -> float:
	return WIND + float(_points.size() - 1) * LEAP + HOLD


func _play_sfx() -> void:
	if _sfx == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_sfx_ms < SFX_MIN_MS:
		return
	_last_sfx_ms = now
	_sfx.pitch_scale = randf_range(1.05, 1.30)
	_sfx.play()


# ---------------- 形状（移植自 pixelfx lightning/_lib.gd，MIT） ----------------

func _rebuild() -> void:
	_paths.clear()
	var redraw := int(_age / REDRAW)
	for i in _points.size() - 1:
		var a := _points[i]
		var b := _points[i + 1]
		var length := a.distance_to(b)
		if length < 0.5:
			_paths.append([{"pts": [[a.x, a.y], [b.x, b.y]], "w": 1.0}])
			continue
		_rng.seed = _play_id * 31 + i * 131 + redraw * 7
		var bow := -length * _rng.randf_range(0.05, 0.15)
		var forks := FORKS if length >= MIN_FORK_LEN else 0.0
		var bolt := _bowed(_rng, a.x, a.y, b.x, b.y, bow, JAG, forks)
		_paths.append(bolt["paths"])


func _zigzag(rng: RandomNumberGenerator, x0: float, y0: float, x1: float, y1: float, jag: float, forks: float, w: float = 1.0, depth: int = 0) -> Dictionary:
	var out := {"paths": []}
	var length := Vector2(x1 - x0, y1 - y0).length()
	var pts: Array = [[x0, y0], [x1, y1]]
	var off := length * jag
	while pts.size() < 2 + int(length / 3.0):
		var nxt: Array = [pts[0]]
		for i in pts.size() - 1:
			var ax: float = pts[i][0]
			var ay: float = pts[i][1]
			var bx: float = pts[i + 1][0]
			var by: float = pts[i + 1][1]
			var l := Vector2(bx - ax, by - ay).length()
			if l <= 0.0:
				l = 1.0
			var o := rng.randf_range(-off, off)
			nxt.append([(ax + bx) * 0.5 + (-(by - ay) / l) * o, (ay + by) * 0.5 + ((bx - ax) / l) * o])
			nxt.append([bx, by])
		pts = nxt
		off *= 0.52
	out["paths"].append({"pts": pts, "w": w})
	if depth < 2 and forks > 0.0:
		for i in range(2, pts.size() - 3):
			if rng.randf() < forks / (1.0 + float(depth)) / maxf(4.0, float(pts.size()) / 6.0):
				var ax: float = pts[i][0]
				var ay: float = pts[i][1]
				var bx: float = pts[mini(pts.size() - 1, i + 3)][0]
				var by: float = pts[mini(pts.size() - 1, i + 3)][1]
				var ang := atan2(by - ay, bx - ax) + (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.35, 0.9)
				var l := (length - (float(i) / float(pts.size())) * length) * rng.randf_range(0.25, 0.55)
				out["paths"].append_array(_zigzag(rng, ax, ay, ax + cos(ang) * l, ay + sin(ang) * l, jag * 1.1, forks, w * 0.55, depth + 1)["paths"])
	return out


func _bowed(rng: RandomNumberGenerator, x0: float, y0: float, x1: float, y1: float, bow: float, jag: float, forks: float) -> Dictionary:
	var length := Vector2(x1 - x0, y1 - y0).length()
	if length <= 0.0:
		length = 1.0
	var nx := -(y1 - y0) / length
	var ny := (x1 - x0) / length
	var mx := (x0 + x1) * 0.5 + nx * bow + rng.randf_range(-2.0, 2.0)
	var my := (y0 + y1) * 0.5 + ny * bow
	var a := _zigzag(rng, x0, y0, mx, my, jag, forks)
	var b := _zigzag(rng, mx, my, x1, y1, jag, forks)
	var paths: Array = [{"pts": (a["paths"][0]["pts"] as Array) + (b["paths"][0]["pts"] as Array).slice(1), "w": 1.0}]
	paths.append_array((a["paths"] as Array).slice(1))
	paths.append_array((b["paths"] as Array).slice(1))
	return {"paths": paths}


# ---------------- 绘制 ----------------

func _draw() -> void:
	if _points.size() < 2:
		return
	for h in _paths.size():
		var start := WIND + float(h) * LEAP
		if _age < start:
			continue
		var land := start + LEAP
		var paths: Array = _paths[h]
		if _age < land:
			var u := clampf((_age - start) / LEAP, 0.0, 1.0)
			_draw_paths(paths, u, 1.0, true)
		else:
			var k := _link_level(h, land)
			if k > 0.0:
				_draw_paths(paths, 1.0, k, false)
	for i in _nodes.size():
		var flash_at: float = _nodes[i]["flash_at"]
		if _age >= flash_at:
			_draw_node(i, (_age - flash_at) / FLASH)


func _link_level(h: int, land: float) -> float:
	var a := _age - land
	if a < 0.1:
		return [1.0, 0.72, 1.0][floori(a * 30.0) % 3]
	return 0.82 + 0.18 * sin(_age * 61.0 + float(h) * 1.7)


func _draw_paths(paths: Array, up_to: float, k: float, leap: bool) -> void:
	for q in paths:
		var w: float = q["w"]
		var trunk := w >= 1.0
		if not trunk and k < 0.5:
			continue
		var pts := _to_packed(q["pts"])
		if leap and trunk:
			var count := maxi(2, int(ceil(float(pts.size()) * up_to)))
			pts = pts.slice(0, count)
			if pts.size() >= 1:
				_draw_head(pts[pts.size() - 1])
		if pts.size() < 2:
			continue
		var hw := 4.0 if trunk else 2.0
		var bw := 2.0 if trunk else 1.0
		draw_polyline(pts, _with_alpha(BODY, 0.08 * k), 7.0 if trunk else 4.0)
		draw_polyline(pts, _with_alpha(HALO, HALO.a * k), hw)
		draw_polyline(pts, _with_alpha(BODY, k), bw)
		draw_polyline(pts, _with_alpha(CORE, k), 1.0)


func _draw_head(p: Vector2) -> void:
	var r := 9.0 + float(_power) * 1.2
	draw_texture_rect(GLOW_TEX, Rect2(p - Vector2(r, r), Vector2(r * 2, r * 2)), false, _with_alpha(BODY, 0.35))
	draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), WHITE)


func _draw_node(i: int, q: float) -> void:
	if q >= 1.0:
		return
	var k := 1.0 - q
	var p := _points[i]
	var gr := 7.0 + float(_power)
	draw_texture_rect(GLOW_TEX, Rect2(p - Vector2(gr, gr), Vector2(gr * 2, gr * 2)), false, _with_alpha(BODY, 0.30 * k))
	draw_circle(p, 1.0 + 4.0 * k, _with_alpha(WHITE, 0.9 * k))
	draw_arc(p, 2.0 + 9.0 * q, 0.0, TAU, 20, _with_alpha(BODY, 0.7 * k), 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = _play_id * 53 + i * 29 + 7
	for a in 2:
		var ang := rng.randf_range(0.0, TAU)
		var dir := Vector2(cos(ang), sin(ang))
		var side := dir.orthogonal()
		var p0 := p + dir * 2.0
		var p1 := p + dir * rng.randf_range(6.0, 10.0) + side * rng.randf_range(-3.0, 3.0)
		draw_line(p0, p1, _with_alpha(BODY, 0.6 * k), 1.0)
	var t := q * FLASH
	var sparks: Array = _nodes[i]["sparks"]
	for s in sparks:
		var pos: Vector2 = p + s["v"] * t + Vector2(0, 150.0) * t * t
		draw_rect(Rect2(Vector2(roundf(pos.x), roundf(pos.y)) - Vector2(1, 1), Vector2(2, 2)), _with_alpha(SPARK, 0.9 * k))


func _to_packed(pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(roundf(p[0]), roundf(p[1])))
	return out


func _with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, clampf(a, 0.0, 1.0))


func _make_sparks(i: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _play_id * 97 + i * 41 + 13
	var out: Array = []
	var count := 4 + _power
	for k in count:
		var ang := rng.randf_range(0.0, TAU)
		var speed := rng.randf_range(40.0, 120.0)
		out.append({"v": Vector2(cos(ang), sin(ang)) * speed})
	return out
