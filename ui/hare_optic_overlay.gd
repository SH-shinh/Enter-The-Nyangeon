extends CanvasLayer

# Hare 锁定态战术目镜全屏滤镜宿主：
# - Game.screen_filters=true：屏幕读取版（BackBufferCopy + hare_optic.gdshader），
#   夜视混色/色差/扫描线/数字雨；
# - Game.screen_filters=false：移动端安全版（MobileShade 压暗 + MobileGlow 加色），
#   不读取屏幕纹理，中央保持原画。
# 关闭时四个节点都隐藏，无渲染开销。

@onready var back_buffer: BackBufferCopy = $BackBufferCopy
@onready var filter: ColorRect = $Filter
@onready var mobile_shade: ColorRect = $MobileShade
@onready var mobile_glow: ColorRect = $MobileGlow

var _tween: Tween = null
var _active: bool = false
var _open: float = 0.0


func _ready() -> void:
	add_to_group("ScreenFilterOverlay")
	_sync_resolution()
	_set_open(0.0)
	_hide_all()


func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	if on:
		visible = true
	# 淡出期间保持当前模式的节点可见，等 Tween 结束再统一隐藏。
	_show_mode(_use_screen_filter(), true)
	_kill_tween()
	var target: float = 1.0 if on else 0.0
	_tween = create_tween()
	_tween.tween_method(_set_open, _open, target, 0.45 if on else 0.28)
	if not on:
		_tween.tween_callback(_hide_all)


## 总开关切换时即时刷新（由 game_option 遍历 ScreenFilterOverlay 组调用）。
func refresh_filter() -> void:
	if not _active:
		_hide_all()
		return
	_show_mode(_use_screen_filter(), true)


# 保底关闭：立即清掉滤镜，不等 Tween（回合结束/商店/节点释放）。
func force_off() -> void:
	_kill_tween()
	_set_open(0.0)
	_hide_all()
	_active = false
	visible = false


func _use_screen_filter() -> bool:
	return bool(Game.screen_filters)


func _show_mode(screen_mode: bool, on: bool) -> void:
	back_buffer.visible = screen_mode and on
	filter.visible = screen_mode and on
	mobile_shade.visible = (not screen_mode) and on
	mobile_glow.visible = (not screen_mode) and on


func _hide_all() -> void:
	back_buffer.visible = false
	filter.visible = false
	mobile_shade.visible = false
	mobile_glow.visible = false


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _set_open(value: float) -> void:
	_open = value
	for material in _materials():
		material.set_shader_parameter("open", value)


func _materials() -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	for rect in [filter, mobile_shade, mobile_glow]:
		var material := rect.material as ShaderMaterial
		if material != null:
			result.append(material)
	return result


func _sync_resolution() -> void:
	var width: float = float(ProjectSettings.get_setting("display/window/size/viewport_width", 640))
	var height: float = float(ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	for material in _materials():
		material.set_shader_parameter("resolution", Vector2(width, height))
