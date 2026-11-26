extends CanvasLayer

## 隐身屏幕滤镜宿主：只做边缘折射/冷色，中心与 HUD 保持清晰。
## 关闭时 BackBufferCopy 与 Filter 都隐藏，无每帧 shader 成本。
## 由 Game.screen_filters（屏幕读取滤镜总开关）门控。

@onready var back_buffer: BackBufferCopy = $BackBufferCopy
@onready var filter: ColorRect = $Filter

## 屏幕滤镜使用的逻辑分辨率；默认按实际窗口 1280×720，不再读 640×360 设计 viewport。
@export var resolution_override: Vector2 = Vector2(1280, 720)

var _tween: Tween = null
var _active: bool = false


func _ready() -> void:
	add_to_group("ScreenFilterOverlay")
	_sync_resolution()
	_hide_now()


func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	if not on and not filter.visible:
		return
	_apply(on)


## 总开关切换时即时刷新（由 game_option 遍历 ScreenFilterOverlay 组调用）。
func refresh_filter() -> void:
	if not _active:
		_hide_now()
		return
	_apply(true)


func _apply(on: bool) -> void:
	if not Game.screen_filters:
		_hide_now()
		return
	var mat := filter.material as ShaderMaterial
	if mat == null:
		_hide_now()
		return
	visible = true
	back_buffer.visible = true
	filter.visible = true
	var cur_raw = mat.get_shader_parameter("open")
	var cur: float = 0.0 if cur_raw == null else float(cur_raw)
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(
		func(v: float) -> void: mat.set_shader_parameter("open", v),
		cur, 1.0 if on else 0.0, 0.22
	)
	if not on:
		_tween.tween_callback(_hide_now)


## 回合结束/死亡/换角色：立即关闭，不等 Tween。
func force_off() -> void:
	_kill_tween()
	var mat := filter.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("open", 0.0)
	_hide_now()
	_active = false


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _hide_now() -> void:
	back_buffer.visible = false
	filter.visible = false
	visible = false


func _sync_resolution() -> void:
	var mat := filter.material as ShaderMaterial
	if mat == null:
		return
	var size := resolution_override
	if size.x <= 0.0 or size.y <= 0.0:
		size = Vector2(1280, 720)
	mat.set_shader_parameter("resolution", size)
