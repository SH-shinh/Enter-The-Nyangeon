extends CanvasLayer

## 联机：本地玩家倒地时的全屏灰度遮罩 + 短暂慢动作（复刻联机版 game_over_page.player_down_screen）。
## 纯本地表现，不影响其它端；复用本体 shaders/motion_screen.gdshader。

const MOTION_SHADER := preload("res://shaders/motion_screen.gdshader")
const SLOW_MO_SCALE: float = 0.1
const SLOW_MO_SEC: float = 0.5

var _rect: ColorRect = null
var _mat: ShaderMaterial = null
var _tween: Tween = null


func _ready() -> void:
	layer = 100
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mat = ShaderMaterial.new()
	_mat.shader = MOTION_SHADER
	_mat.set_shader_parameter("f", 0.3)
	_mat.set_shader_parameter("v", 15.0)
	_mat.set_shader_parameter("grayscale", true)
	_rect = ColorRect.new()
	_rect.color = Color(1, 1, 1, 1)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func show_down() -> void:
	visible = true
	_rect.modulate.a = 0.0
	_tween_kill()
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", 1.0, 0.25)
	_hit_stop()


func hide_down() -> void:
	Engine.time_scale = 1.0
	if not visible:
		return
	_tween_kill()
	_tween = create_tween()
	_tween.tween_property(_rect, "modulate:a", 0.0, 0.25)
	_tween.tween_callback(_on_fade_out_done)


func _on_fade_out_done() -> void:
	visible = false


func _tween_kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _hit_stop() -> void:
	Engine.time_scale = SLOW_MO_SCALE
	# ignore_time_scale=true：以真实时间计时恢复，避免被自身 time_scale 拖长
	await get_tree().create_timer(SLOW_MO_SEC, true, false, true).timeout
	Engine.time_scale = 1.0
