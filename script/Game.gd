extends Node

signal game_mode_changed

# 当前操作设备：0 键鼠 / 1 触屏 / 2 手柄。
# 只用于「隐藏/显示触摸 UI」「准星瞄准源」「交互提示图标」这类表现层选择，
# 不得作为「输入是否生效」的唯一真相（角色被 player_stop/can_* 锁住时任何设备都推不动）。
enum ControlMode { MOUSE = 0, TOUCH = 1, GAMEPAD = 2 }

# 触摸后这段时间内，非触摸事件（尤其是手柄轴）不能立刻把模式夺走。
const TOUCH_PRIORITY_MSEC := 400
# 手柄轴：>= 该值视为明确推杆，立即判手柄；介于 HOLD~IMMEDIATE 之间需保持 150ms。
const GAMEPAD_AXIS_IMMEDIATE := 0.9
const GAMEPAD_AXIS_HOLD := 0.75
const GAMEPAD_HOLD_MSEC := 150
# 触摸设备上，外接键鼠/手柄静默这么久后自动回落到触屏模式（避免蓝牙设备睡眠后模式永久锁死）。
const EXTERNAL_IDLE_FALLBACK_MSEC := 5000
const INPUT_TRACE_LIMIT := 32
const GAMEPLAY_ACTIONS := [&"move_left", &"move_right", &"move_up", &"move_down", &"move_jump", &"fire", &"kick", &"reload", &"EX_skill"]

const SAVE_STORE := preload("res://script/scene_data_store.gd")
const SAVE_PATH := SAVE_STORE.PRIMARY
const SAVE_PATH_TMP := SAVE_STORE.TEMP
const SAVE_PATH_BAK := SAVE_STORE.BACKUP
const CONFIG_PATH := "user://config.ini"
var _save_store = SAVE_STORE.new()
var _loading_playerdata := false

var version_number: String = "v0.5.3.1a-test"


var on_full_screen: bool
var shake_screen: bool
var resolution: int
var vsync_mode: bool

# 渲染帧率上限（设置项）：滑条档位 → FPS_CHOICES；索引 0 = 无限制。
# 启用 2D 物理插值后，帧率不再需要对齐物理 60Hz；此项仅用于性能/功耗取舍。
const FPS_CHOICES: Array[int] = [0, 60, 75, 90, 120, 144]
var max_fps_index: int = 1

# 伤害数字频率上限（设置项）：0=关 / 1=低(≈2.5Hz) / 2=中(≈3.3Hz) / 3=高(≈5Hz) / 4=最高(≈10Hz,默认)。
# 实际频率 = max(该上限, FPS 自适应档)，即自适应只在此基础上再降、不会更密。
var damage_text_freq: int = 4

# 特效频率上限（设置项）：0=关 / 1=×4间隔 / 2=×3 / 3=×2 / 4=×1(最高,默认)。
# 特效最短间隔 = 基准间隔 * 手动系数 * FPS 系数（FPS 越低间隔越大 = 只降频率）。
var effect_freq: int = 4

# 受击闪白频率上限（设置项）：0=关 / 1=×4间隔 / 2=×3 / 3=×2 / 4=×1(最高,默认)。独立于 effect_freq。
var hit_flash_freq: int = 4

# 弹壳数量上限（设置项）：档位索引 → CASING_CAP_LEVELS，0=关，默认 2(=64)，最高 4(=256)。
# 静止弹壳每帧零开销（已关物理、同纹理合批），上限主要影响池内节点数与长期留存量。
const CASING_CAP_LEVELS := [0, 32, 64, 128, 256]
var casing_level: int = 2

# 2D 物理插值（设置项，默认关）：高刷屏下让物理体在物理 tick 间平滑、消除 judder；
# 迁移期部分视觉仍有错位风险，故默认关，运行期经 SceneTree.physics_interpolation 生效。
var physics_interp: bool = false

# CRT 屏幕滤镜（设置项，默认关）：autoload CRTOverlay 全屏叠加扫描线/荫罩。
# 关闭时滤镜节点隐藏，无渲染开销。
var crt_filter: bool = false

# 屏幕读取型全屏滤镜总开关：覆盖 CRT / Hare 目镜 / Kotama 隐身影屏。
# PC 默认开、移动端默认关（缺省值由 load_config 按平台决定）；关闭时 Hare 目镜
# 回退到不读屏幕的安全 overlay，CRT/隐身影屏不渲染。移动端开启会提示机型风险。
var screen_filters: bool = false

var control_mode: int = ControlMode.MOUSE

# 当前平台是否有触摸输入（移动端/触屏笔记本）。测试、mod 可覆写。
var touch_device_available: bool = false
# 是否为移动端（Android/iOS）。桌面触屏也 touch_device_available=true，但默认仍是键鼠。
var is_mobile_platform: bool = false
# 失焦自动暂停是否启用（默认仅移动端）。测试、mod 可覆写。
var focus_pause_enabled: bool = false
# GameEvents.pause_lock 的镜像，用于失焦兜底与看门狗判断「暂停是否由演出/升级持锁」。
var pause_locked: bool = false

var _touch_priority_until_msec: int = 0
var _last_non_touch_input_msec: int = 0
var _last_input_desc: String = ""
var _last_input_msec: int = 0
var _input_trace: Array[String] = []

# 手柄轴候选（0.75~0.9 需保持 150ms 才判手柄）。
var _gamepad_candidate_axis: int = -1
var _gamepad_candidate_device: int = -1
var _gamepad_candidate_msec: int = 0

# 按下沿/抬起沿跟踪：防止按键重复、鼠标/手柄卡键反复夺走模式。
var _held_mouse: Dictionary = {}
var _held_keys: Dictionary = {}
var _held_joy_buttons: Dictionary = {}
var _touch_fingers: Dictionary = {}
var _touch_session_start_msec: int = 0

var _focus_lost: bool = false
var _suspicious_since_msec: int = 0
var _last_warn_msec: int = 0
var _last_watchdog_msec: int = 0

var game_language: String

# 开发者模式（设置项）：手动把 user://config.ini 的 [game] developer_mode 改为 true 即开启；
# 用于解锁调试作弊菜单，正式版保持 false。
var dev_mode: bool = false

# 调试作弊：一击必杀（运行时开关，不写 config.ini）。由 health_component 结算时读取。
var one_hit_kill: bool = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_mobile_platform = OS.has_feature("mobile")
	touch_device_available = _detect_touch_device()
	focus_pause_enabled = is_mobile_platform
	var now := Time.get_ticks_msec()
	_last_non_touch_input_msec = now
	_last_watchdog_msec = now
	load_config()
	# 帧率上限由设置项（max_fps_index）决定：全平台默认 60（索引 1），0=无限制；
	# 启用 2D 物理插值后高刷下不再需要强制对齐物理 60Hz。
	apply_max_fps()
	# 2D 物理插值由设置项（physics_interp）决定，全平台默认关；运行期覆写 SceneTree 属性。
	apply_physics_interp()
	GameEvents.pause_lock.connect(_on_pause_lock)
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# ModManager 挂载/注册支援后同步读档，避免旧 Resource 存档在挂载前加载失败。
	reset_control_mode()
	GameEvents.round_start.connect(reset_control_mode)

func reset_control_mode():
	# 移动端默认触屏；桌面默认鼠标。回合边界复位，避免设备事件把 control_mode 永久锁死。
	_touch_priority_until_msec = 0
	_gamepad_candidate_axis = -1
	_last_non_touch_input_msec = Time.get_ticks_msec()
	var target := _default_control_mode()
	if control_mode != target:
		control_mode = target
		_trace_input("mode=%d <- reset" % target)
		game_mode_changed.emit()

func _default_control_mode() -> int:
	# 桌面触屏不等于移动端：PC 上即使有触摸屏，默认仍是键鼠；真实触摸事件仍会切 TOUCH。
	return ControlMode.TOUCH if is_mobile_platform else ControlMode.MOUSE

func _detect_touch_device() -> bool:
	return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	_tick_gamepad_candidate(now)
	_tick_external_idle_fallback(now)
	_tick_control_watchdog(now)

# 0.75~0.9 的手柄轴候选：保持 150ms 仍在该区间才判手柄，滤掉漂移/抖动。
func _tick_gamepad_candidate(now: int) -> void:
	if _gamepad_candidate_axis < 0:
		return
	if now - _gamepad_candidate_msec < GAMEPAD_HOLD_MSEC:
		return
	var value := Input.get_joy_axis(_gamepad_candidate_device, _gamepad_candidate_axis)
	if absf(value) >= GAMEPAD_AXIS_HOLD:
		_note_input(now, "joy_axis_hold dev=%d axis=%d" % [_gamepad_candidate_device, _gamepad_candidate_axis], true)
		_apply_control_mode(ControlMode.GAMEPAD, "joy_axis_hold")
	_gamepad_candidate_axis = -1

# 外接键鼠/手柄静默（蓝牙睡眠、断开、接收器掉线）后，把触摸 UI 带回来。
# 只在移动端启用；桌面触屏即使有触摸能力也不自动弹出触摸 UI（避免桌面键鼠被抢）。
func _tick_external_idle_fallback(now: int) -> void:
	if not is_mobile_platform or control_mode == ControlMode.TOUCH:
		return
	if get_tree().paused:
		return
	var player := _local_player()
	if player == null or not _player_alive(player):
		return
	if now - _last_non_touch_input_msec < EXTERNAL_IDLE_FALLBACK_MSEC:
		return
	if _has_held_gameplay_input():
		return
	_touch_priority_until_msec = now + TOUCH_PRIORITY_MSEC
	_apply_control_mode(ControlMode.TOUCH, "external_idle_fallback")

# 只告警不自动改状态：把「世界在跑但角色/暂停异常」的现场写进日志，供真机定位。
func _tick_control_watchdog(now: int) -> void:
	if now - _last_watchdog_msec < 1000:
		return
	_last_watchdog_msec = now
	var suspicious := ""
	var player := _local_player()
	if player != null and _player_alive(player):
		var pause_visible := _is_pause_ui_visible()
		var stopped := bool(player.get("player_stop"))
		var downed := bool(player.get("is_downed"))
		if not get_tree().paused and stopped and not downed and not pause_visible:
			suspicious = "player_stop"
		elif get_tree().paused and not pause_visible and not pause_locked:
			suspicious = "paused_without_ui"
	if suspicious.is_empty():
		_suspicious_since_msec = 0
		return
	if _suspicious_since_msec == 0:
		_suspicious_since_msec = now
	if now - _suspicious_since_msec < 3000:
		return
	if now - _last_warn_msec < 10000:
		return
	_last_warn_msec = now
	push_warning("[input] control lock: %s %s" % [suspicious, JSON.stringify(input_debug_snapshot())])

func _on_pause_lock(locked: bool) -> void:
	pause_locked = locked
	_trace_input("pause_lock=%s" % locked)

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	_trace_input("joy_connection dev=%d connected=%s pads=%s" % [device, connected, str(Input.get_connected_joypads())])
	if not connected and Input.get_connected_joypads().is_empty() and control_mode == ControlMode.GAMEPAD:
		# 只回退模式；不要在这里全量释放动作，否则会把键盘正按住的 move_* / fire 一起清掉。
		reset_control_mode()
	_resync_mode_ui()

func _on_focus_lost() -> void:
	if _focus_lost:
		return
	_focus_lost = true
	_trace_input("focus_out")
	_release_all_gameplay_inputs()
	_resync_mode_ui()
	# 只有在移动端单机、未暂停、无演出/升级暂停锁、且暂停由本体负责时才自动暂停；
	# 联机 LAN 会话由 coop mod 接管暂停，避免抢它的 player_stop/暂停语义。
	if not focus_pause_enabled or get_tree().paused:
		return
	if ExtensionHooks.is_hook_active(&"pause_visibility") and ExtensionHooks.intercept_named(&"is_lan_session", []):
		return
	var player := _local_player()
	if player == null or not _player_alive(player):
		return
	var pause_screen = player.get("pause_screen")
	if pause_screen != null and pause_screen.has_method("show_pause"):
		pause_screen.call("show_pause")

func _on_focus_gained() -> void:
	if not _focus_lost:
		return
	_focus_lost = false
	_trace_input("focus_in")
	_release_all_gameplay_inputs()
	_resync_mode_ui()

func _resync_mode_ui() -> void:
	# 模式未变时也重发一次，让 UI 在回前台/断连后重新按 control_mode 求值。
	game_mode_changed.emit()

func _apply_control_mode(mode: int, source: String = "") -> void:
	if mode < ControlMode.MOUSE or mode > ControlMode.GAMEPAD:
		return
	if control_mode == mode:
		return
	control_mode = mode
	_trace_input("mode=%d <- %s" % [mode, source])
	if dev_mode:
		print("[input] control_mode=%d (%s)" % [mode, source])
	game_mode_changed.emit()

# 公开给测试/mod：改模式并走同一套 UI 同步。
func set_control_mode(mode: int) -> void:
	_apply_control_mode(mode, "api")

func _local_player() -> Node:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("Player")

func _player_alive(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	var stats = player.get("stats")
	if stats == null:
		return false
	var hp = stats.get("hp")
	return hp != null and int(hp) > 0

func _is_pause_ui_visible() -> bool:
	var player := _local_player()
	if player == null:
		return false
	var pause_screen = player.get("pause_screen")
	return pause_screen != null and is_instance_valid(pause_screen) and bool(pause_screen.get("visible"))

func _has_held_gameplay_input() -> bool:
	for action in GAMEPLAY_ACTIONS:
		if Input.is_action_pressed(action):
			return true
	for action in [&"aim_left", &"aim_right", &"aim_up", &"aim_down"]:
		if Input.is_action_pressed(action):
			return true
	return false

# 失焦/回前台/三指恢复共用：把可能卡住的输入状态清干净。
func _release_all_gameplay_inputs() -> void:
	for action in GAMEPLAY_ACTIONS:
		Input.action_release(action)
	# 失焦期间可能永远收不到 release，按下沿表必须一并清空，否则下一次真实按下会被当成重复。
	_held_mouse.clear()
	_held_keys.clear()
	_held_joy_buttons.clear()
	_touch_fingers.clear()
	_gamepad_candidate_axis = -1
	var player := _local_player()
	if player == null or not is_instance_valid(player):
		return
	var gun = player.get("gun")
	if gun != null and is_instance_valid(gun):
		gun.set("is_shoot", false)
	player.set("is_jump_request", false)

func input_debug_snapshot() -> Dictionary:
	var now := Time.get_ticks_msec()
	var ui_state := UIMode.debug_state()
	var snapshot := {
		"control_mode": control_mode,
		"touch_device": touch_device_available,
		"paused": get_tree().paused if is_inside_tree() else null,
		"pause_locked": pause_locked,
		"pause_visible": _is_pause_ui_visible(),
		"time_scale": Engine.time_scale,
		"window_focused": DisplayServer.window_is_focused(),
		"joypads": Input.get_connected_joypads(),
		"mouse_mode": Input.mouse_mode,
		"ui_mode": ui_state.get("mode"),
		"ui_mode_base": ui_state.get("base"),
		"ui_cursor_visible": ui_state.get("cursor_visible"),
		"ui_entries": ui_state.get("entries"),
		"last_input": _last_input_desc,
		"last_input_age_ms": now - _last_input_msec if _last_input_msec > 0 else -1,
		"touch_priority_left_ms": maxi(0, _touch_priority_until_msec - now),
		"trace": _input_trace.duplicate(),
	}
	var player := _local_player()
	if player != null and is_instance_valid(player):
		var stats = player.get("stats")
		var gun = player.get("gun")
		var pause_screen = player.get("pause_screen")
		var hud = get_tree().get_first_node_in_group("GameUI")
		snapshot["player"] = {
			"player_stop": player.get("player_stop"),
			"can_control": player.get("can_control"),
			"can_move": player.get("can_move"),
			"can_jump": player.get("can_jump"),
			"is_downed": player.get("is_downed"),
			"is_stunned": player.call("is_stunned") if player.has_method("is_stunned") else null,
			"hp": stats.get("hp") if stats != null else null,
			"gun_can_shoot": gun.get("can_shoot") if gun != null else null,
			"gun_is_shoot": gun.get("is_shoot") if gun != null else null,
			"pause_screen_visible": pause_screen.get("visible") if pause_screen != null else null,
		}
		snapshot["hud_visible"] = hud.get("visible") if hud != null else null
		snapshot["joypad_visible"] = hud.get_node_or_null("VirtualJoypad").get("visible") if hud != null and hud.get_node_or_null("VirtualJoypad") != null else null
	return snapshot

# 移动端三指点击的逃生口：现场快照 + 释放动作 + 回平台默认模式 + 清玩家硬停/异常暂停。
func recover_control_state() -> Dictionary:
	var snapshot := input_debug_snapshot()
	push_warning("[input] recover_control_state: " + JSON.stringify(snapshot))
	_release_all_gameplay_inputs()
	_touch_priority_until_msec = 0
	_gamepad_candidate_axis = -1
	_apply_control_mode(_default_control_mode(), "recover")
	game_mode_changed.emit()
	var player := _local_player()
	if player == null or not _player_alive(player):
		return snapshot
	if get_tree().paused and not _is_pause_ui_visible() and not pause_locked:
		get_tree().paused = false
	if not bool(player.get("is_downed")):
		player.set("player_stop", false)
	return snapshot

func _trace_input(text: String) -> void:
	_input_trace.append("%d %s" % [Time.get_ticks_msec(), text])
	while _input_trace.size() > INPUT_TRACE_LIMIT:
		_input_trace.pop_front()

func _note_input(now: int, desc: String, non_touch: bool) -> void:
	_last_input_desc = desc
	_last_input_msec = now
	if non_touch:
		_last_non_touch_input_msec = now
	_trace_input(desc)

func apply_max_fps():
	var idx: int = clampi(max_fps_index, 0, FPS_CHOICES.size() - 1)
	max_fps_index = idx
	Engine.max_fps = FPS_CHOICES[idx]

# 运行期应用 2D 物理插值开关（默认关）。SceneTree 属性可在运行期安全切换。
func apply_physics_interp():
	var tree := get_tree()
	if tree != null:
		tree.physics_interpolation = physics_interp

# 当前弹壳上限（0 = 关闭抛壳）。设置项越界时 clamp 到档位表范围。
func casing_cap() -> int:
	return int(CASING_CAP_LEVELS[clampi(casing_level, 0, CASING_CAP_LEVELS.size() - 1)])

func pause_press():
	var event = InputEventAction.new()
	event.action = "pause"
	event.pressed = true
	Input.parse_input_event(event)

func _notification(what):
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		pause_press()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_on_focus_lost()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_on_focus_gained()

# _input 先于 GUI：触摸即使落在 STOP Control 上也能被这里看到，用于可靠回切触屏。
func _input(event: InputEvent) -> void:
	_track_input_device(event)

func _unhandled_input(event: InputEvent) -> void:
	_track_input_device(event)

func _track_input_device(event: InputEvent) -> void:
	var now := Time.get_ticks_msec()
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		_track_touch_finger(st)
		_touch_priority_until_msec = now + TOUCH_PRIORITY_MSEC
		_gamepad_candidate_axis = -1
		_note_input(now, "touch idx=%d pressed=%s canceled=%s" % [st.index, st.pressed, st.canceled], false)
		_apply_control_mode(ControlMode.TOUCH, "touch")
		return
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touch_priority_until_msec = now + TOUCH_PRIORITY_MSEC
		_gamepad_candidate_axis = -1
		_note_input(now, "touch_drag idx=%d" % sd.index, false)
		_apply_control_mode(ControlMode.TOUCH, "touch_drag")
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			_held_mouse[mb.button_index] = false
			_last_non_touch_input_msec = now
			return
		var was_held := bool(_held_mouse.get(mb.button_index, false))
		_held_mouse[mb.button_index] = true
		_last_non_touch_input_msec = now
		if was_held or now < _touch_priority_until_msec:
			return
		if mb.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_note_input(now, "mouse_btn %d" % mb.button_index, true)
		# 关卡内准星就是指针：鼠标点击只切键鼠模式，不改 Input.mouse_mode（鼠标/准星由 UIMode 模式栈统一派生）。
		_apply_control_mode(ControlMode.MOUSE, "mouse_button")
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		var code: int = key.keycode if key.keycode != 0 else key.physical_keycode
		if not key.pressed:
			_held_keys.erase(code)
			_last_non_touch_input_msec = now
			return
		var was_down := bool(_held_keys.get(code, false))
		_held_keys[code] = true
		_last_non_touch_input_msec = now
		# echo（按键重复）与重复按下不算新意图；Android 蓝牙键盘的 echo 不可靠，按下沿表兜底。
		if key.echo or was_down or now < _touch_priority_until_msec:
			return
		if key.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_note_input(now, "key %d" % code, true)
		_apply_control_mode(ControlMode.MOUSE, "key")
		return
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		var button_key: int = int(jb.device) * 100 + int(jb.button_index)
		if not jb.pressed:
			_held_joy_buttons.erase(button_key)
			_last_non_touch_input_msec = now
			return
		var was_button := bool(_held_joy_buttons.get(button_key, false))
		_held_joy_buttons[button_key] = true
		_last_non_touch_input_msec = now
		if was_button or now < _touch_priority_until_msec:
			return
		_note_input(now, "joy_btn dev=%d btn=%d" % [jb.device, jb.button_index], true)
		_apply_control_mode(ControlMode.GAMEPAD, "joy_button")
		return
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		_last_non_touch_input_msec = now
		if now < _touch_priority_until_msec:
			_gamepad_candidate_axis = -1
			return
		if absf(jm.axis_value) >= GAMEPAD_AXIS_IMMEDIATE:
			_note_input(now, "joy_axis dev=%d axis=%d v=%.2f" % [jm.device, jm.axis, jm.axis_value], true)
			_apply_control_mode(ControlMode.GAMEPAD, "joy_axis")
		elif absf(jm.axis_value) >= GAMEPAD_AXIS_HOLD:
			_gamepad_candidate_axis = jm.axis
			_gamepad_candidate_device = jm.device
			_gamepad_candidate_msec = now
		else:
			_gamepad_candidate_axis = -1
		return

func _track_touch_finger(st: InputEventScreenTouch) -> void:
	var now := Time.get_ticks_msec()
	if st.canceled or not st.pressed:
		_touch_fingers.erase(st.index)
		return
	if _touch_fingers.is_empty():
		_touch_session_start_msec = now
	_touch_fingers[st.index] = true
	if _touch_fingers.size() >= 3 and is_mobile_platform and now - _touch_session_start_msec <= 500:
		_touch_fingers.clear()
		recover_control_state()


func write_to_log(message: String):
	# 1. 定义文件夹路径和文件路径
	# 2. 检查文件夹是否存在，不存在就创建
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("scorebound"):
		dir.make_dir("scorebound")
		print("创建了 scorebound 文件夹")
	
	# 3. 现在可以安全地创建/写入文件了
	var file = FileAccess.open("user://scorebound/game_score.txt", FileAccess.READ_WRITE)
	if not file:
		file = FileAccess.open("user://scorebound/game_score.txt", FileAccess.WRITE)
	if file:
		file.seek_end()
		# 写入带时间戳的信息
		var timestamp = Time.get_datetime_string_from_system()
		file.store_line("%s - %s" % [timestamp, message])
		file.close()
	else:
		push_error("无法打开日志文件进行写入！")

func save_record_as_json(file_path: String, record: Dictionary):
	var file = FileAccess.open(file_path, FileAccess.READ_WRITE)
	if not file:
		file = FileAccess.open(file_path, FileAccess.WRITE)
	
	file.seek_end()
	var json_line = JSON.stringify(record)
	if file.get_position() > 0:
		file.store_string("\n" + json_line)
	else:
		file.store_string(json_line)
	file.close()

func save_all_records_as_json(file_path: String, records: Array):
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("无法写入记录文件: " + file_path)
		return
	for r in records:
		file.store_line(JSON.stringify(r))
	file.close()

func load_all_records_as_json(file_path: String) -> Array:
	var records = []
	if not FileAccess.file_exists(file_path):
		return records
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	while file.get_position() < file.get_length():
		var line = file.get_line()
		if line.strip_edges() != "":
			var record = JSON.parse_string(line)
			if record != null:
				records.append(record)
	file.close()
	return records

	#
	#dir.list_dir_begin()  # 开始遍历
	#var file_name = dir.get_next()
	#
	#while file_name != "":
	## 检查是否是文件（不是文件夹）
		#if not dir.current_is_dir():
	## 检查文件后缀
			#if file_name.ends_with(extension):
				#files.append(file_name)
		#file_name = dir.get_next()
	#
	#dir.list_dir_end()  # 结束遍历
	#return files

func save_playerdata():
	if _loading_playerdata:
		return false
	var playerdata = SceneData.new()
	playerdata.save_version = SceneData.SAVE_VERSION
	playerdata.player_pyroxenes = PlayerData.player_pyroxenes
	playerdata.character = PlayerData.character
	playerdata.group = PlayerData.group
	playerdata.clothes_group = PlayerData.clothes_group
	playerdata.now_clothes = PlayerData.now_clothes
	playerdata.game_mode = PlayerData.game_mode
	playerdata.support_savedata = SceneData.support_progress(SupportData.support_data)
	playerdata.game_support_id = SupportData.selected_support_id
	return _write_scene_data(playerdata)

func _write_scene_data(playerdata: SceneData) -> bool:
	return _save_store.save_data(playerdata)

func load_playerdata():
	var playerdata = _save_store.load_data()
	if playerdata == null:
		return
	_loading_playerdata = true
	var needs_save: bool = _save_store.recovered or playerdata.save_version < SceneData.SAVE_VERSION
	if playerdata.save_version < SceneData.SAVE_VERSION:
		_migrate_scene_data(playerdata)
	
	PlayerData.game_mode = playerdata.game_mode
	SupportData.restore_progress(playerdata.support_savedata, playerdata.game_support_id)
	# 迁移清理：已下线的 "hujiu" 模式；放在 pyroxenes 赋值（触发存档）之前，避免残留被写回。
	if PlayerData.game_mode.has("hujiu"):
		PlayerData.game_mode.remove_at(PlayerData.game_mode.find("hujiu"))
	
	if !playerdata.character.is_empty():
		PlayerData.character = playerdata.character
	if !playerdata.group.is_empty():
		PlayerData.group = playerdata.group
	if !playerdata.clothes_group.is_empty():
		PlayerData.clothes_group = playerdata.clothes_group
	if !playerdata.now_clothes.is_empty():
		PlayerData.now_clothes = playerdata.now_clothes
	# 放最后：setter 会触发即时存档，此时其余字段应已恢复完毕。
	PlayerData.player_pyroxenes = playerdata.player_pyroxenes
	_loading_playerdata = false
	if needs_save:
		save_playerdata()

func _migrate_scene_data(playerdata: SceneData):
	if playerdata.save_version < 3:
		var selected := "null"
		if playerdata.game_support != null:
			selected = playerdata.game_support.support_id
			# 缺失资源占位保留对象身份，从已购字典的 key 取真实 ID，不能猜文件名。
			for id in playerdata.support_savedata:
				var entry = playerdata.support_savedata[id]
				if entry is Dictionary and entry.get("resource") == playerdata.game_support:
					selected = str(id)
					break
		playerdata.game_support_id = selected if not selected.is_empty() else "null"
		playerdata.support_savedata = SceneData.support_progress(playerdata.support_savedata)
		playerdata.game_support = null
	# 旧档升级入口。旧格式（save_version 缺省为 0）的顶层字段一直是有效真源，
	# 原 game_version 快照只是冗余副本，无需读取；支援字段已在上方转为 v3 纯数据。
	# 未来结构变更时按 playerdata.save_version 逐级追加迁移逻辑。
	playerdata.save_version = SceneData.SAVE_VERSION

func save_config():
	var config := ConfigFile.new()
	
	config.set_value("game", "full_screen", on_full_screen)
	config.set_value("game", "shake_screen", shake_screen)
	config.set_value("game", "resolution", resolution)
	config.set_value("game", "vsync_mode", vsync_mode)
	config.set_value("game", "max_fps_index", max_fps_index)
	config.set_value("game", "physics_interp", physics_interp)
	config.set_value("game", "crt_filter", crt_filter)
	config.set_value("game", "screen_filters", screen_filters)
	config.set_value("game", "game_language", game_language)
	config.set_value("game", "damage_text_freq", damage_text_freq)
	config.set_value("game", "effect_freq", effect_freq)
	config.set_value("game", "hit_flash_freq", hit_flash_freq)
	config.set_value("game", "casing_level", casing_level)
	config.set_value("game", "developer_mode", dev_mode)
	
	config.set_value("audio", "master", SoundManager.get_volume(SoundManager.Bus.MASTER))
	config.set_value("audio", "sfx", SoundManager.get_volume(SoundManager.Bus.SFX))
	config.set_value("audio", "bgm", SoundManager.get_volume(SoundManager.Bus.BGM))
	config.set_value("audio", "voice", SoundManager.get_volume(SoundManager.Bus.VOICE))
	
	config.save(CONFIG_PATH)

func load_config():
	
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("scorebound"):
		dir.make_dir("scorebound")
		print("创建了 scorebound 文件夹")
	
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	
	on_full_screen = config.get_value("game", "full_screen", false)
	shake_screen = config.get_value("game", "shake_screen", true)
	resolution = config.get_value("game", "resolution", 0)
	vsync_mode = config.get_value("game", "vsync_mode", true)
	max_fps_index = int(config.get_value("game", "max_fps_index", 1))
	physics_interp = bool(config.get_value("game", "physics_interp", false))
	crt_filter = bool(config.get_value("game", "crt_filter", false))
	screen_filters = bool(config.get_value("game", "screen_filters", not OS.has_feature("mobile")))
	game_language = config.get_value("game", "game_language", "zh_CN")
	damage_text_freq = config.get_value("game", "damage_text_freq", 4)
	effect_freq = config.get_value("game", "effect_freq", 4)
	hit_flash_freq = config.get_value("game", "hit_flash_freq", 4)
	casing_level = int(config.get_value("game", "casing_level", 2))
	dev_mode = config.get_value("game", "developer_mode", false)
	
	# 桌面端的全屏/分辨率/垂直同步设置不能作用到移动端：
	# 移动端执行 WINDOW_MODE_WINDOWED 会退出沉浸式全屏，导致系统通知栏一直显示。
	# 移动端保持导出预设的 immersive_mode 即可。
	if not OS.has_feature("mobile"):
		if on_full_screen == true:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		
		if vsync_mode == true:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		else:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		
		if resolution == 0:
			DisplayServer.window_set_size(Vector2i(1280,720))
		elif resolution == 1:
			DisplayServer.window_set_size(Vector2i(1600,900))
		elif resolution == 2:
			DisplayServer.window_set_size(Vector2i(1920,1080))
	
	TranslationServer.set_locale(game_language)
	
	SoundManager.set_volume(
		SoundManager.Bus.MASTER,
		config.get_value("audio", "master", 1.0)
	)
	
	SoundManager.set_volume(
		SoundManager.Bus.SFX,
		config.get_value("audio", "sfx", 1.0)
	)
	
	SoundManager.set_volume(
		SoundManager.Bus.BGM,
		config.get_value("audio", "bgm", 0.65)
	)
	
	SoundManager.set_volume(
		SoundManager.Bus.VOICE,
		config.get_value("audio", "voice", 1.0)
	)
