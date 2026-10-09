extends OptionMenu

@onready var full_screen: Control = %FullScreen
@onready var shake: Control = %Shake
@onready var v_sync: Control = %VSync
@onready var damage_freq: HSlider = %DamageFreq
@onready var damage_freq_value: Label = %DamageFreqValue
@onready var effect_freq: HSlider = %EffectFreq
@onready var effect_freq_value: Label = %EffectFreqValue
@onready var hit_flash_freq: HSlider = %HitFlashFreq
@onready var hit_flash_freq_value: Label = %HitFlashFreqValue
@onready var resolutions_block: Control = %ResolutionsTouchBlock
@onready var mobile_notice = %MobileNotice
@onready var resolutions: OptionButton = %Resolutions

func _ready():
	setting_status()
	full_screen.mouse_entered.connect(mouse_on_full_screen)
	full_screen.mouse_exited.connect(mouse_out_full_screen)
	full_screen.gui_input.connect(mouse_selected_full_screen)
	shake.mouse_entered.connect(mouse_on_shake)
	shake.mouse_exited.connect(mouse_out_shake)
	shake.gui_input.connect(mouse_selected_shake)
	v_sync.mouse_entered.connect(mouse_on_vs)
	v_sync.mouse_exited.connect(mouse_out_vs)
	v_sync.gui_input.connect(mouse_selected_vs)
	resolutions.item_selected.connect(_on_resolutions_item_selected)
	damage_freq.value_changed.connect(_on_damage_freq_value_changed)
	effect_freq.value_changed.connect(_on_effect_freq_value_changed)
	hit_flash_freq.value_changed.connect(_on_hit_flash_freq_value_changed)
	resolutions_block.gui_input.connect(_on_resolutions_touch_block_gui_input)
	resolutions_block.mouse_filter = (
		Control.MOUSE_FILTER_STOP if OS.has_feature("mobile") else Control.MOUSE_FILTER_IGNORE
	)

func menu_show():
	super()
	setting_status()

func _show_mobile_notice():
	mobile_notice.notice("option_mobile_only_notice")

func _on_resolutions_touch_block_gui_input(event: InputEvent):
	if event is InputEventScreenTouch and event.pressed:
		_show_mobile_notice()

func mouse_on_full_screen():
	if Game.on_full_screen == false:
		full_screen.get_node("AnimationPlayer").play("full_on")
	else:
		full_screen.get_node("AnimationPlayer").play("selected_out")

func mouse_out_full_screen():
	if Game.on_full_screen == false:
		full_screen.get_node("AnimationPlayer").play("full_out")
	else:
		full_screen.get_node("AnimationPlayer").play("selected")

func mouse_selected_full_screen(event: InputEvent):

	# 移动端由导出预设的沉浸式全屏接管，桌面端的窗口模式会关闭全屏、露出系统通知栏。
	if OS.has_feature("mobile"):
		if event is InputEventScreenTouch and event.pressed:
			_show_mobile_notice()
		return

	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		if Game.on_full_screen == false:
			Game.on_full_screen = true
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			full_screen.get_node("AnimationPlayer").play("selected")
			Game.save_config()
		else:
			Game.on_full_screen = false
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			full_screen.get_node("AnimationPlayer").play("full_out")
			Game.save_config()

	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		if Game.on_full_screen == false:
			Game.on_full_screen = true
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			full_screen.get_node("AnimationPlayer").play("selected")
			Game.save_config()
		else:
			Game.on_full_screen = false
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			full_screen.get_node("AnimationPlayer").play("full_out")
			Game.save_config()

func mouse_on_shake():
	if Game.shake_screen == false:
		shake.get_node("AnimationPlayer").play("full_on")
	else:
		shake.get_node("AnimationPlayer").play("selected_out")

func mouse_out_shake():
	if Game.shake_screen == false:
		shake.get_node("AnimationPlayer").play("full_out")
	else:
		shake.get_node("AnimationPlayer").play("selected")

func mouse_selected_shake(event: InputEvent):

	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		if Game.shake_screen == false:
			Game.shake_screen = true
			shake.get_node("AnimationPlayer").play("selected")
			Game.save_config()
		else:
			Game.shake_screen = false
			shake.get_node("AnimationPlayer").play("full_out")
			Game.save_config()

	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		if Game.shake_screen == false:
			Game.shake_screen = true
			shake.get_node("AnimationPlayer").play("selected")
			Game.save_config()
		else:
			Game.shake_screen = false
			shake.get_node("AnimationPlayer").play("full_out")
			Game.save_config()

func mouse_on_vs():
	if Game.vsync_mode == false:
		v_sync.get_node("AnimationPlayer").play("full_on")
	else:
		v_sync.get_node("AnimationPlayer").play("selected_out")

func mouse_out_vs():
	if Game.vsync_mode == false:
		v_sync.get_node("AnimationPlayer").play("full_out")
	else:
		v_sync.get_node("AnimationPlayer").play("selected")

func mouse_selected_vs(event: InputEvent):

	# 移动端垂直同步由系统/驱动控制，避免桌面窗口设置生效。
	if OS.has_feature("mobile"):
		if event is InputEventScreenTouch and event.pressed:
			_show_mobile_notice()
		return

	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		if Game.vsync_mode == false:
			Game.vsync_mode = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			v_sync.get_node("AnimationPlayer").play("selected")
			Game.save_config()
		else:
			Game.vsync_mode = false
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			v_sync.get_node("AnimationPlayer").play("full_out")
			Game.save_config()

	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		if Game.vsync_mode == false:
			Game.vsync_mode = true
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			v_sync.get_node("AnimationPlayer").play("selected")
			Game.save_config()
		else:
			Game.vsync_mode = false
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			v_sync.get_node("AnimationPlayer").play("full_out")
			Game.save_config()


func setting_status():
	if Game.on_full_screen == true:
		full_screen.get_node("AnimationPlayer").play("selected")
	else:
		full_screen.get_node("AnimationPlayer").play("full_out")

	resolutions.selected = Game.resolution

	if Game.shake_screen == true:
		shake.get_node("AnimationPlayer").play("selected")
	else:
		shake.get_node("AnimationPlayer").play("full_out")

	if Game.vsync_mode == true:
		v_sync.get_node("AnimationPlayer").play("selected")
	else:
		v_sync.get_node("AnimationPlayer").play("full_out")

	damage_freq.set_value_no_signal(Game.damage_text_freq)
	damage_freq_value.text = _damage_freq_text(Game.damage_text_freq)
	effect_freq.set_value_no_signal(Game.effect_freq)
	effect_freq_value.text = _effect_freq_text(Game.effect_freq)
	hit_flash_freq.set_value_no_signal(Game.hit_flash_freq)
	hit_flash_freq_value.text = _effect_freq_text(Game.hit_flash_freq)

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
