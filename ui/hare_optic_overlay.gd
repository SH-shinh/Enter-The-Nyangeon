extends CanvasLayer

# Hare 锁定态战术目镜全屏滤镜宿主：
# 中心不覆盖、边缘渐变（edge_mask），叠加扫描线/扫描带/暗角/数字雨。
# 关闭时 BackBufferCopy 与 Filter 都隐藏，无渲染开销。

@onready var back_buffer: BackBufferCopy = $BackBufferCopy
@onready var filter: ColorRect = $Filter

var _tween: Tween = null
var _active: bool = false


func _ready() -> void:
	_sync_resolution()
	back_buffer.visible = false
	filter.visible = false


func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	if on:
		visible = true
	# 移动端对 hint_screen_texture 有兼容风险（与 CRT overlay 一致，直接禁用）。
	if OS.has_feature("mobile"):
		back_buffer.visible = false
		filter.visible = false
		return
	var mat := filter.material as ShaderMaterial
	if mat == null:
		return
	back_buffer.visible = true
	filter.visible = true
	var cur: float = float(mat.get_shader_parameter("open"))
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(
		func(v: float): mat.set_shader_parameter("open", v),
		cur, 1.0 if on else 0.0, 0.45 if on else 0.28
	)
	if not on:
		_tween.tween_callback(func():
			back_buffer.visible = false
			filter.visible = false
		)


# 保底关闭：立即清掉滤镜，不等 Tween（回合结束/商店/节点释放）。
func force_off() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var mat := filter.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("open", 0.0)
	back_buffer.visible = false
	filter.visible = false
	_active = false
	visible = false


func _sync_resolution() -> void:
	var mat := filter.material as ShaderMaterial
	if mat == null:
		return
	var width: float = float(ProjectSettings.get_setting("display/window/size/viewport_width", 640))
	var height: float = float(ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	mat.set_shader_parameter("resolution", Vector2(width, height))
