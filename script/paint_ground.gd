class_name PaintGround
extends Node2D

## 地面颜料层（Splatoon 风格）：4 种喷溅形状各一个 MultiMeshInstance2D，
## 每块颜料 = 一个实例（形状 + 变换 + 实例色），零粒子、零每帧逻辑。
## 4 个 draw call（形状数），与颜料数量无关；贴图为灰阶，实例色染三色。
##
## 外部拿到的 handle 是稳定 id；内部按形状做 swap-remove 压缩，
## handle -> {shape, index} 映射保证删除后其它 handle 不失效。
## 每形状容量满时环形覆盖最旧实例（最后一层兜底；上层通常已按区域上限主动移除）。

const SHAPE_COUNT := 4
const CAP_PER_SHAPE := 256
## 与 script/floor_paint.tscn 的三色粒子对齐：0=Pink / 1=Blue / 2=Yellow。
const PAINT_COLORS: Array[Color] = [
	Color(0.894118, 0.384314, 0.588235, 1.0),
	Color(0.219608, 0.654902, 0.698039, 1.0),
	Color(0.899196, 0.741214, 0.224535, 1.0),
]
const PAINT_TEXTS: Array[Texture2D] = [
	preload("res://sprites/effects/paint_splat_0.png"),
	preload("res://sprites/effects/paint_splat_1.png"),
	preload("res://sprites/effects/paint_splat_2.png"),
	preload("res://sprites/effects/paint_splat_3.png"),
]
const PAINT_SHADER: Shader = preload("res://shaders/paint_splat.gdshader")

var _mms: Array[MultiMesh] = []
var _nodes: Array[MultiMeshInstance2D] = []
var _handles: Dictionary = {}              # handle -> {shape:int, index:int}
var _index_handle: Array[Dictionary] = []  # shape -> (index -> handle)
var _counts: Array[int] = []
var _cursors: Array[int] = []
var _next_handle: int = 0


func _ready() -> void:
	# 复用 main.backlayer_clear_unit() 的清场路径（FloorLayer 下 Texture 组）。
	if not is_in_group("Texture"):
		add_to_group("Texture")
	_setup()


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
		_nodes.append(node)
		_index_handle.append({})
		_counts.append(0)
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
		# 兜底覆盖：最旧实例被新颜料顶掉，其 handle 失效。
		idx = _cursors[s]
		_cursors[s] = (idx + 1) % CAP_PER_SHAPE
		var overwritten := int(_index_handle[s].get(idx, -1))
		if overwritten != -1:
			_handles.erase(overwritten)
	var handle := _next_handle
	_next_handle += 1
	var a: float = angle if not is_nan(angle) else randf_range(0.0, TAU)
	var flip: float = -1.0 if randf() < 0.5 else 1.0
	var size: float = maxf(1.0, radius) * 2.0 * maxf(0.1, paint_scale)
	mm.set_instance_transform_2d(idx, Transform2D(a, Vector2(size * flip, size), 0.0, pos))
	mm.set_instance_color(idx, PAINT_COLORS[clampi(color, 0, PAINT_COLORS.size() - 1)])
	mm.visible_instance_count = _counts[s]
	_handles[handle] = {"shape": s, "index": idx}
	_index_handle[s][idx] = handle
	return handle


func remove_paint(handle: int) -> void:
	if not _handles.has(handle):
		return
	var entry: Dictionary = _handles[handle]
	var s := int(entry["shape"])
	var idx := int(entry["index"])
	var mm := _mms[s]
	var last: int = _counts[s] - 1
	if idx != last:
		var last_handle := int(_index_handle[s][last])
		mm.set_instance_transform_2d(idx, mm.get_instance_transform_2d(last))
		mm.set_instance_color(idx, mm.get_instance_color(last))
		_index_handle[s][idx] = last_handle
		_handles[last_handle]["index"] = idx
		_index_handle[s].erase(last)
	_handles.erase(handle)
	_counts[s] -= 1
	mm.visible_instance_count = _counts[s]


func clear() -> void:
	_handles.clear()
	for s in SHAPE_COUNT:
		if s < _counts.size():
			_counts[s] = 0
			_cursors[s] = 0
			_index_handle[s].clear()
			_mms[s].visible_instance_count = 0


func clear_pool() -> void:
	clear()


func paint_count() -> int:
	var total := 0
	for c in _counts:
		total += c
	return total
