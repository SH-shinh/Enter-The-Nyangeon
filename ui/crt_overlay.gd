extends CanvasLayer

# 全屏 CRT 滤镜宿主（autoload CRTOverlay）。
# 采样根视口 backbuffer 并叠加扫描线/荫罩/VHS 干扰；关闭时两个节点都隐藏，无渲染开销。
# BackBufferCopy 必须保留：Godot 2D 的 hint_screen_texture 每帧只在首个使用者处
# 自动拷贝一次，游戏内已有描边/冲击波等中途读取屏幕的 shader，否则这里会拿到半帧画面。
# 渲染由 Game.crt_filter（二级偏好）与 Game.screen_filters（总开关）共同决定。

@onready var back_buffer: BackBufferCopy = $BackBufferCopy
@onready var filter: ColorRect = $Filter

func _ready() -> void:
	add_to_group("ScreenFilterOverlay")
	_sync_resolution()
	set_enabled(Game.crt_filter)

func set_enabled(on: bool) -> void:
	var active: bool = on and Game.screen_filters
	back_buffer.visible = active
	filter.visible = active

## 总开关切换时即时刷新（由 game_option 遍历 ScreenFilterOverlay 组调用）。
func refresh_filter() -> void:
	set_enabled(Game.crt_filter)

# 图案网格跟随设计分辨率：扫描线与游戏逻辑像素 1:1，荫罩频率由 shader 按 width/3 推导。
func _sync_resolution() -> void:
	var material := filter.material as ShaderMaterial
	if material == null:
		return
	var width: float = float(ProjectSettings.get_setting("display/window/size/viewport_width", 640))
	var height: float = float(ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	material.set_shader_parameter("resolution", Vector2(width, height))
