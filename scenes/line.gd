extends Line2D

## 子弹拖尾：按真实轨迹记录世界坐标点；单线双色（外线长度渐变 + 圆头胶囊内芯）。
##
## 2026-11-18 全量：14 个玩家弹场景统一为一条 Line2D，双线时代的 Line2 已删除。
## 性能：默认 60Hz 采样、固定点数（max_points）、单次 points 赋值；屏幕外剔除；
##       <38fps 时降到 30Hz。150 发玩家弹 = 151 draw call（双线时代 301）。
## 视觉：内芯由 shaders/bullet_trail_core.gdshader 按「局部坐标到拖尾弦的距离」画胶囊，
##       两端自然圆头；每条线 duplicate 一份材质并写端点/半宽 uniform（共享材质会互相覆盖）。
## 这里只做视觉；子弹伤害/碰撞/联机同步都不受影响。

@export var width_f: float
## 采样频率：默认与物理同频（60Hz）；只有低帧率降级时才降到 30Hz。
@export var update_hz: float = 60.0
## 点数上限；至少按 2 点处理（1 点无法画线）。
@export var max_points: int = 3
## 与上一个记录点距离小于该值就不加点：慢速 / 滞空弹不再白刷。
@export var min_step_px: float = 2.0
## 到屏幕中心超过该距离：隐藏并停止加点（屏幕半对角线约 367px）。
@export var cull_radius: float = 520.0
## 回到 cull_radius - cull_hysteresis 内才恢复，避免贴边闪烁。
@export var cull_hysteresis: float = 60.0

var p1: Node
var scale_mult: float = 1
# 空闲时停物理：池中大量空闲拖尾不再每帧回调。
var is_idle: bool = false:
	set(v):
		is_idle = v
		set_physics_process(not v)

const CHECK_EVERY := 12
## 内芯半宽 = 外线半宽 × 旧内线比例 7/12 × 旧 width_curve（尾 0.527 / 头 0.670）。
## kei 的 10.5/18 比例相同，所以全场景共用一个系数。
const CORE_WIDTH_RATIO := 7.0 / 12.0
const CORE_CURVE_TAIL := 0.527
const CORE_CURVE_HEAD := 0.670

var _buf := PackedVector2Array()
var _accum: float = 0.0
var _frame: int = 0
var _cull_hidden: bool = false
var _fps_severe: bool = false
## 每线独立材质：胶囊端点 uniform 不能共享。
var _core_material: ShaderMaterial = null

func _ready():
	p1 = get_parent()
	clear_points()
	_setup_core_material()
	update_width()

func reset():
	_buf.clear()
	points = _buf
	_accum = 0.0
	_frame = 0
	_cull_hidden = false
	_fps_severe = false
	visible = true

func update_width():
	self.set_width( width_f * scale_mult)
	_apply_core_widths()

func _physics_process(delta):
	if is_idle:
		return
	_frame += 1
	# 错峰检查（每 CHECK_EVERY 帧一次，按实例 id 分散，避免同帧尖峰）。
	if _frame % CHECK_EVERY == get_instance_id() % CHECK_EVERY:
		_refresh_visibility()
	if _cull_hidden:
		return
	var hz: float = update_hz
	if _fps_severe:
		hz = minf(hz, 30.0)
	if hz > 0.0:
		_accum += delta
		if _accum < 1.0 / hz:
			return
		_accum = 0.0
	var position: Vector2 = p1.position
	if not _buf.is_empty() \
			and position.distance_squared_to(_buf[_buf.size() - 1]) < min_step_px * min_step_px:
		return
	_buf.append(position)
	var cap: int = maxi(2, max_points)
	while _buf.size() > cap:
		_buf.remove_at(0)
	# 一次赋值替代 add_point + remove_point 两次引擎调用。
	points = _buf
	_update_core_capsule()

func _setup_core_material() -> void:
	if _core_material != null:
		return
	if material is ShaderMaterial:
		_core_material = (material as ShaderMaterial).duplicate() as ShaderMaterial
		material = _core_material

func _apply_core_widths() -> void:
	if _core_material == null:
		return
	var line_width: float = width_f * scale_mult
	var core_half: float = line_width * 0.5 * CORE_WIDTH_RATIO
	_core_material.set_shader_parameter("core_half_tail", core_half * CORE_CURVE_TAIL)
	_core_material.set_shader_parameter("core_half_head", core_half * CORE_CURVE_HEAD)

func _update_core_capsule() -> void:
	if _core_material == null or _buf.is_empty():
		return
	_core_material.set_shader_parameter("tail_pos", _buf[0])
	_core_material.set_shader_parameter("head_pos", _buf[_buf.size() - 1])

# 每 CHECK_EVERY 帧：按「屏幕外 / 低帧率」决定隐藏或降采样。
func _refresh_visibility():
	var fps := _fps_value()
	if _fps_severe:
		if fps >= 45.0 or fps <= 0.0:
			_fps_severe = false
	elif fps > 0.0 and fps < 38.0:
		_fps_severe = true
	var was_culled := _cull_hidden
	_cull_hidden = _is_cull_hidden()
	visible = not _cull_hidden
	if _cull_hidden:
		_accum = 0.0
		# 隐藏期间子弹已经走远，恢复时要重新开始，否则旧点会连出一条跨屏长线。
		if not was_culled and not _buf.is_empty():
			_buf.clear()
			points = _buf

func _fps_value() -> float:
	if PoolManager != null and PoolManager.has_method("get_fps_ema"):
		return PoolManager.get_fps_ema()
	# 兜底：没有共享 EMA 时用引擎帧率（headless/未知返回 0，会被当作健康）。
	return float(Engine.get_frames_per_second())

func _is_cull_hidden() -> bool:
	var center := _view_center()
	if center == Vector2.INF:
		return false
	var point: Vector2 = global_position
	if p1 is Node2D:
		point = (p1 as Node2D).global_position
	var distance: float = point.distance_to(center)
	if _cull_hidden:
		return distance > maxf(cull_radius - cull_hysteresis, 0.0)
	return distance > cull_radius

func _view_center() -> Vector2:
	var viewport := get_viewport()
	if viewport != null:
		var camera := viewport.get_camera_2d()
		if camera != null:
			return camera.get_screen_center_position()
	var tree := get_tree()
	if tree != null:
		var player := tree.get_first_node_in_group("Player")
		if player is Node2D:
			return (player as Node2D).global_position
	return Vector2.INF
