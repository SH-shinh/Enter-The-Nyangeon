class_name PaintGround
extends Node2D

## 地面颜料层（Splatoon 风格）：4 种喷溅形状各一个 MultiMeshInstance2D，
## 每块颜料 = 一个实例（形状 + 变换 + 实例色），零粒子、几乎零每帧逻辑。
## 4 个 draw call（形状数），与颜料数量无关。
##
## 单色：贴图是纯白 alpha mask，颜色完全由实例色（Pink/Blue/Yellow）决定。
## 像素化出现/消失：实例色 alpha 编码相对时间（>0 出生 / <0 = -死亡），
## 每帧把 now_sec 传给 4 个材质，shader 按 4px 块随机阈值逐块展开/消散。
##
## 外部 handle 稳定；remove_paint 只标记死亡动画（不立即压缩槽位），
## 槽位在每形状容量满时被环形覆盖，普通局内 1024 块足够。

const SHAPE_COUNT := 4
const CAP_PER_SHAPE := 256
## 与 script/floor_paint.tscn 的三色粒子对齐：0=Pink / 1=Blue / 2=Yellow。
const PAINT_COLORS: Array[Color] = [
	Color(0.546, 0.126, 0.308, 1.0),
	Color(0.042, 0.336, 0.434, 1.0),
	Color(0.602, 0.434, 0.028, 1.0),
]
const PAINT_TEXTS: Array[Texture2D] = [
	preload("res://sprites/effects/paint_splat_0.png"),
	preload("res://sprites/effects/paint_splat_1.png"),
	preload("res://sprites/effects/paint_splat_2.png"),
	preload("res://sprites/effects/paint_splat_3.png"),
]
const PAINT_SHADER: Shader = preload("res://shaders/paint_splat.gdshader")

var _mms: Array[MultiMesh] = []
var _mats: Array[ShaderMaterial] = []
var _handles: Dictionary = {}              # handle -> {shape:int, index:int}
var _index_handle: Array[Dictionary] = []  # shape -> (index -> handle)
var _counts: Array[int] = []               # 已占用槽位（含死亡动画中的实例）
var _live_counts: Array[int] = []          # 有效（未死亡）块数
var _cursors: Array[int] = []
var _next_handle: int = 0
var _t0: float = 0.0


func _ready() -> void:
	# 复用 main.backlayer_clear_unit() 的清场路径（FloorLayer 下 Texture 组）。
	if not is_in_group("Texture"):
		add_to_group("Texture")
	_t0 = Time.get_ticks_msec() / 1000.0
	_setup()
	set_process(true)


func _process(_delta: float) -> void:
	var now := _now()
	for mat in _mats:
		mat.set_shader_parameter("now_sec", now)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0 - _t0


func _setup() -> void:
	if not _mms.is_empty():
		return
	for i in SHAPE_COUNT:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		mm.mesh = quad
		mm.instance_count = CAP_PER_SHAPE
		mm.visible_instance_count = 0
		var mat := ShaderMaterial.new()
		mat.shader = PAINT_SHADER
		mat.set_shader_parameter("paint_tex", PAINT_TEXTS[i])
		var node := MultiMeshInstance2D.new()
		node.name = "Shape%d" % i
		node.multimesh = mm
		node.material = mat
		add_child(node)
		_mms.append(mm)
		_mats.append(mat)
		_index_handle.append({})
		_counts.append(0)
		_live_counts.append(0)
		_cursors.append(0)


## 写入一块颜料，返回稳定 handle。
## radius 为视觉半径（px）；angle 为 NAN 时随机；shape < 0 时随机形状。
func add_paint(pos: Vector2, color: int, radius: float, angle: float = NAN, paint_scale: float = 1.0, shape: int = -1) -> int:
	if _mms.is_empty():
		_setup()
	var s: int = shape if shape >= 0 and shape < SHAPE_COUNT else randi() % SHAPE_COUNT
	var mm := _mms[s]
	var idx: int
	if _counts[s] < CAP_PER_SHAPE:
		idx = _counts[s]
		_counts[s] += 1
	else:
		# 槽位满：环形覆盖最旧；若覆盖到有效块要同步减少 live。
		idx = _cursors[s]
		_cursors[s] = (idx + 1) % CAP_PER_SHAPE
		var overwritten := int(_index_handle[s].get(idx, -1))
		if overwritten != -1:
			_handles.erase(overwritten)
			_index_handle[s].erase(idx)
			_live_counts[s] = maxi(0, _live_counts[s] - 1)
	var handle := _next_handle
	_next_handle += 1
	var a: float = angle if not is_nan(angle) else randf_range(0.0, TAU)
	var flip: float = -1.0 if randf() < 0.5 else 1.0
	var size: float = maxf(1.0, radius) * 2.0 * maxf(0.1, paint_scale)
	mm.set_instance_transform_2d(idx, Transform2D(a, Vector2(size * flip, size), 0.0, pos))
	var base: Color = PAINT_COLORS[clampi(color, 0, PAINT_COLORS.size() - 1)]
	# 每块颜料 ±20% 明度抖动（保持色相）；alpha 仍存出生时间，不能被抖动覆盖。
	var k := randf_range(0.8, 1.2)
	var c := Color(
		clampf(base.r * k, 0.0, 1.0),
		clampf(base.g * k, 0.0, 1.0),
		clampf(base.b * k, 0.0, 1.0),
		1.0,
	)
	# alpha 存出生时间（相对 _t0），shader 用 now_sec - birth 做像素化展开。
	mm.set_instance_color(idx, Color(c.r, c.g, c.b, maxf(_now(), 0.001)))
	mm.visible_instance_count = _counts[s]
	_handles[handle] = {"shape": s, "index": idx}
	_index_handle[s][idx] = handle
	_live_counts[s] += 1
	return handle


## 标记死亡动画（像素化消散），不立即压缩槽位；handle 立即失效。
func remove_paint(handle: int) -> void:
	if not _handles.has(handle):
		return
	var entry: Dictionary = _handles[handle]
	var s := int(entry["shape"])
	var idx := int(entry["index"])
	var mm := _mms[s]
	var c := mm.get_instance_color(idx)
	mm.set_instance_color(idx, Color(c.r, c.g, c.b, -maxf(_now(), 0.001)))
	_handles.erase(handle)
	_index_handle[s].erase(idx)
	_live_counts[s] = maxi(0, _live_counts[s] - 1)


func clear() -> void:
	_handles.clear()
	for s in SHAPE_COUNT:
		if s < _counts.size():
			_counts[s] = 0
			_live_counts[s] = 0
			_cursors[s] = 0
			_index_handle[s].clear()
			_mms[s].visible_instance_count = 0


func clear_pool() -> void:
	clear()


func paint_count() -> int:
	var total := 0
	for c in _live_counts:
		total += c
	return total
