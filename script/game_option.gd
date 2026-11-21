extends OptionMenu

@onready var full_screen = %FullScreen
@onready var shake = %Shake
@onready var v_sync = %VSync
@onready var damage_freq: HSlider = %DamageFreq
@onready var damage_freq_value: Label = %DamageFreqValue
@onready var effect_freq: HSlider = %EffectFreq
@onready var effect_freq_value: Label = %EffectFreqValue
@onready var hit_flash_freq: HSlider = %HitFlashFreq
@onready var hit_flash_freq_value: Label = %HitFlashFreqValue
@onready var casing_cap: HSlider = %CasingCap
@onready var casing_cap_value: Label = %CasingCapValue
@onready var resolutions_block: Control = %ResolutionsTouchBlock
@onready var mobile_notice = %MobileNotice
@onready var resolutions: OptionButton = %Resolutions
@onready var max_fps: HSlider = %MaxFps
@onready var max_fps_value: Label = %MaxFpsValue
@onready var physics_interp = %PhysicsInterp
@onready var crt_filter = %Crt
@onready var row_display: Control = %RowDisplay
@onready var row_advanced: Control = %RowAdvanced
@onready var row_crt: Control = %RowCrt
@onready var full_screen_label: Control = %FullScreenLabel
@onready var v_sync_label: Control = %VSyncLabel
@onready var physics_interp_label: Control = %PhysicsInterpLabel

func _ready():
	_bind_toggle(full_screen, Game.on_full_screen, _set_full_screen, false)
	_bind_toggle(shake, Game.shake_screen, _set_shake)
	_bind_toggle(v_sync, Game.vsync_mode, _set_vsync, false)
	_bind_toggle(physics_interp, Game.physics_interp, _set_physics_interp)
	_bind_toggle(crt_filter, Game.crt_filter, _set_crt_filter)
	_bind_toggle_label(full_screen, full_screen_label)
	_bind_toggle_label(shake, shake.get_parent().get_node("Label"))
	_bind_toggle_label(v_sync, v_sync_label)
	_bind_toggle_label(physics_interp, physics_interp_label)
	_bind_toggle_label(crt_filter, crt_filter.get_parent().get_node("Label"))
	resolutions.item_selected.connect(_on_resolutions_item_selected)
	damage_freq.value_changed.connect(_on_damage_freq_value_changed)
	effect_freq.value_changed.connect(_on_effect_freq_value_changed)
	hit_flash_freq.value_changed.connect(_on_hit_flash_freq_value_changed)
	casing_cap.value_changed.connect(_on_casing_cap_value_changed)
	max_fps.value_changed.connect(_on_max_fps_value_changed)
	resolutions_block.gui_input.connect(_on_resolutions_touch_block_gui_input)
	resolutions_block.mouse_filter = (
		Control.MOUSE_FILTER_STOP if OS.has_feature("mobile") else Control.MOUSE_FILTER_IGNORE
	)
	setting_status()
	if OS.has_feature("mobile"):
		row_display.hide()
		row_advanced.hide()
		row_crt.hide()

func menu_show():
	super()
	setting_status()

func _bind_toggle(toggle, value: bool, apply: Callable, allow_mobile: bool = true) -> void:
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.set_on(value, false)
	toggle.toggled.connect(func(on: bool):
		_on_toggle_changed(toggle, on, apply, allow_mobile)
	)

func _bind_toggle_label(toggle, label_target: Control) -> void:
	label_target.mouse_filter = Control.MOUSE_FILTER_STOP
	label_target.gui_input.connect(func(event: InputEvent):
		_on_toggle_label_input(toggle, label_target, event)
	)

func _on_toggle_changed(toggle, on: bool, apply: Callable, allow_mobile: bool) -> void:
	# 移动端由导出预设接管全屏/垂直同步；若防御性入口仍可达，则回滚并提示。
	if not allow_mobile and OS.has_feature("mobile"):
		toggle.set_on(not on, false)
		_show_mobile_notice()
		return
	SoundManager.play_sfx("ButtonSounds")
	apply.call(on)

func _on_toggle_label_input(toggle, label: Control, event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		label.accept_event()
		toggle.toggle()
	elif not event.is_echo() and (event.is_action_pressed("shoot") or event.is_action_pressed("ui_accept")):
		label.accept_event()
		toggle.toggle()

func _set_full_screen(on: bool) -> void:
	Game.on_full_screen = on
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)
	Game.save_config()

func _set_shake(on: bool) -> void:
	Game.shake_screen = on
	Game.save_config()

func _set_vsync(on: bool) -> void:
	Game.vsync_mode = on
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED
	)
	Game.save_config()

# 物理插值开关（默认关）：写入设置并运行期应用，随后持久化。
func _set_physics_interp(on: bool) -> void:
	Game.physics_interp = on
	Game.apply_physics_interp()
	Game.save_config()

# CRT 屏幕滤镜开关（默认关）：autoload 缺失时（如部分独立测试入口）静默跳过。
func _set_crt_filter(on: bool) -> void:
	Game.crt_filter = on
	var overlay := get_node_or_null("/root/CRTOverlay")
	if overlay != null:
		overlay.set_enabled(on)
	Game.save_config()

func _show_mobile_notice():
	mobile_notice.notice("option_mobile_only_notice")

func _on_resolutions_touch_block_gui_input(event: InputEvent):
	if event is InputEventScreenTouch and event.pressed:
		_show_mobile_notice()

func setting_status():
	full_screen.set_on(Game.on_full_screen, false)
	resolutions.selected = Game.resolution
	shake.set_on(Game.shake_screen, false)
	v_sync.set_on(Game.vsync_mode, false)
	physics_interp.set_on(Game.physics_interp, false)
	crt_filter.set_on(Game.crt_filter, false)
	damage_freq.set_value_no_signal(Game.damage_text_freq)
	damage_freq_value.text = _damage_freq_text(Game.damage_text_freq)
	effect_freq.set_value_no_signal(Game.effect_freq)
	effect_freq_value.text = _effect_freq_text(Game.effect_freq)
	hit_flash_freq.set_value_no_signal(Game.hit_flash_freq)
	hit_flash_freq_value.text = _effect_freq_text(Game.hit_flash_freq)
	casing_cap.set_value_no_signal(Game.casing_level)
	casing_cap_value.text = _casing_cap_text(Game.casing_level)
	max_fps.set_value_no_signal(Game.max_fps_index)
	max_fps_value.text = _max_fps_text(Game.max_fps_index)

func _on_resolutions_item_selected(index):
	var n: int
	# 移动端分辨率由设备决定，不能也不应改写窗口尺寸。
	if OS.has_feature("mobile"):
		return
	match index:
		0:
			DisplayServer.window_set_size(Vector2i(1280,720))
			n = 0
		1:
			DisplayServer.window_set_size(Vector2i(1600,900))
			n = 1
		2:
			DisplayServer.window_set_size(Vector2i(1920,1080))
			n = 2

	Game.resolution = n
	Game.save_config()

# 伤害数字频率滑条（设置项）：0=关 / 1=低 / 2=中 / 3=高 / 4=最高。
# 这里只负责写入档位与持久化；实际频率由 PoolManager 结合 FPS 自适应计算。
func _on_damage_freq_value_changed(value: float):
	var idx: int = clampi(int(round(value)), 0, 4)
	if idx == Game.damage_text_freq:
		return
	Game.damage_text_freq = idx
	Game.save_config()
	damage_freq_value.text = _damage_freq_text(idx)

func _damage_freq_text(idx: int) -> String:
	match idx:
		0:
			return "0% · " + tr("damage_freq_off")
		1:
			return "25% · ≤2.5Hz"
		2:
			return "50% · ≤3.3Hz"
		3:
			return "75% · ≤5Hz"
	return "100% · ≤10Hz"

# 特效频率滑条（设置项）：0=关 / 1=×4间隔 / 2=×3 / 3=×2 / 4=×1(最高)。
# 写入档位后由 PoolManager 结合基准间隔与 FPS 自适应计算实际最短间隔（只降频率）。
func _on_effect_freq_value_changed(value: float):
	var idx: int = clampi(int(round(value)), 0, 4)
	if idx == Game.effect_freq:
		return
	Game.effect_freq = idx
	Game.save_config()
	effect_freq_value.text = _effect_freq_text(idx)

func _effect_freq_text(idx: int) -> String:
	match idx:
		0:
			return "0% · " + tr("damage_freq_off")
		1:
			return "25% · ×4"
		2:
			return "50% · ×3"
		3:
			return "75% · ×2"
	return "100% · ×1"

# 受击闪白频率滑条（设置项）：独立于 effect_freq：0=关 / 1=×4 / 2=×3 / 3=×2 / 4=×1(最高)。
# 写入档位后由 PoolManager.hit_flash_allowed() 结合 60ms 基准与 FPS 自适应计算间隔。
func _on_hit_flash_freq_value_changed(value: float):
	var idx: int = clampi(int(round(value)), 0, 4)
	if idx == Game.hit_flash_freq:
		return
	Game.hit_flash_freq = idx
	Game.save_config()
	hit_flash_freq_value.text = _effect_freq_text(idx)

# 帧率上限滑条（设置项）：0=无限制 / 1=60 / 2=75 / 3=90 / 4=120 / 5=144。
# 写入档位后立即应用 Engine.max_fps 并持久化。
func _on_max_fps_value_changed(value: float):
	var idx: int = clampi(int(round(value)), 0, Game.FPS_CHOICES.size() - 1)
	if idx == Game.max_fps_index:
		return
	Game.max_fps_index = idx
	Game.apply_max_fps()
	Game.save_config()
	max_fps_value.text = _max_fps_text(idx)

func _max_fps_text(idx: int) -> String:
	if idx <= 0:
		return tr("fps_unlimited")
	return str(Game.FPS_CHOICES[idx])

# 弹壳数量上限滑条（设置项）：0=关 / 32 / 64(默认) / 128 / 256。
# 写入档位后立即同步池上限，并把超出的（最旧的）弹壳回收；0 时清空全部且不再抛壳。
func _on_casing_cap_value_changed(value: float):
	var idx: int = clampi(int(round(value)), 0, Game.CASING_CAP_LEVELS.size() - 1)
	if idx == Game.casing_level:
		return
	Game.casing_level = idx
	Game.save_config()
	casing_cap_value.text = _casing_cap_text(idx)
	PoolManager.apply_casing_limit()

func _casing_cap_text(idx: int) -> String:
	var level: int = clampi(idx, 0, Game.CASING_CAP_LEVELS.size() - 1)
	var cap: int = int(Game.CASING_CAP_LEVELS[level])
	if cap <= 0:
		return "0 · " + tr("damage_freq_off")
	return str(cap)
