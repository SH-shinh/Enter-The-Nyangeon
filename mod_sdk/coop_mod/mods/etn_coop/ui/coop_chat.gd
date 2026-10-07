extends CanvasLayer

## CoopChat：联机聊天室（mod 内，非 autoload）。
## 右侧中间小窗记录本次房间全部消息；Enter 开窗/发送；聚焦时显示鼠标并冻结本地玩家，
## 发送后立即恢复鼠标与操作（窗口仍 2 秒后淡出）；重新聚焦再占用。
## 有新消息时自动显示（PEEK：不聚焦/不占用控件/不拦截鼠标/更透明，2 秒后淡出，新消息重置）。
## 本地玩家 HUD（$GameUI/AmmoPosition）旁挂一个仅图标按钮（scoreboard_icon），供手机端开聊。
## mod 内不使用 class_name，一律 preload。

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const ACTION := "coop_chat"
const BUTTON_ICON := preload("res://ui/scoreboard_icon.png")
const FONT := preload("res://fonts/BoutiqueBitmap9x9_1.9.ttf")
const HIDE_DELAY: float = 2.0
const FADE_TIME: float = 0.25  # 淡出时长(秒)
const PEEK_BG_ALPHA: float = 0.4    # 自动显示时面板背景透明度
const PEEK_INPUT_ALPHA: float = 0.4 # 自动显示时输入框透明度
const FONT_SIZE: int = 9
const BTN_SIZE := Vector2(30, 30)
const BTN_POS := Vector2(220, 66)
const SFX := "ButtonSounds"
# 延迟小字（两个聊天按钮下方）：纯数字 + 按 quality 着色
const PING_FONT := preload("res://fonts/BoutiqueBitmap7x7_1.7.ttf")
const PING_FONT_SIZE: int = 8
const PING_POS := Vector2(BTN_POS.x - 10.0, BTN_POS.y + 32.0)
const PING_SIZE := Vector2(50, 12)
const PING_REFRESH: float = 0.3
const PING_COLOR_GOOD := Color(0.3, 1.0, 0.4, 1.0)
const PING_COLOR_FAIR := Color(1.0, 0.85, 0.2, 1.0)
const PING_COLOR_POOR := Color(1.0, 0.3, 0.25, 1.0)

@onready var _panel: Control = $Panel
@onready var _scroll: ScrollContainer = %Scroll
@onready var _log_box: VBoxContainer = %LogBox
@onready var _input_box: LineEdit = %ChatInput
@onready var _upgrade_btn: TextureButton = %UpgradeChatButton
@onready var _upgrade_ping: Label = %UpgradePingLabel

var _is_open: bool = false
var _composing: bool = false   # true=输入态（聚焦/占用控件）；false=peek（自动显示）
var _orig_bg_alpha: float = 0.9411765
var _prev_mouse_mode: int = Input.MOUSE_MODE_VISIBLE
var _frozen_player: Node = null
var _prev_player_stop: bool = false
var _controls_held: bool = false
var _fade_tween: Tween = null
var _hide_token: int = 0
var _btn: TextureButton = null
var _ping_label: Label = null
var _ping_timer: float = 0.0
var _last_touch_frame: int = -2
var _upgrade_active: bool = false


func _ready() -> void:
	_register_action()
	_input_box.placeholder_text = tr("coop_chat_placeholder")
	_panel.visible = false
	_panel.modulate.a = 0.0
	# 不拦截鼠标：面板整棵子树 IGNORE（输入靠程序聚焦；游玩期不吞点击/不挡开火）
	_set_mouse_ignore(_panel)
	var sb := _panel.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		_orig_bg_alpha = (sb as StyleBoxFlat).bg_color.a
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		coop.chat_received.connect(_on_chat_received)
	GameEvents.game_over.connect(_on_game_over)
	# 升级页期间显示上层按钮（升级页 layer=2，本聊天层 layer=119 盖在其上）
	GameEvents.round_upgrade.connect(_on_upgrade_begin)
	GameEvents.round_upgrade_end.connect(_on_upgrade_end)
	GameEvents.round_upgrade_closing.connect(_on_upgrade_end)
	GameEvents.round_start.connect(_on_upgrade_end)


func _register_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	for kc in [KEY_ENTER, KEY_KP_ENTER]:
		var k := InputEventKey.new()
		k.physical_keycode = kc
		InputMap.action_add_event(ACTION, k)


func _input(event: InputEvent) -> void:
	var coop = CoopNetScript.instance
	var active: bool = coop != null and is_instance_valid(coop) and bool(coop.is_lan_game)
	if not active and not _is_open:
		return
	if _is_open and event.is_action_pressed("ui_cancel"):
		_hide_now()
		get_viewport().set_input_as_handled()
		return
	# 手机端图标按钮：纯显示 + 手动命中判定（避免游玩期吞鼠标/误触）。
	if _button_hit(event):
		_activate()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed(ACTION):
		return
	if not active:
		return
	_activate()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_ensure_button()
	_ensure_upgrade_button()
	_refresh_pings(delta)
	# 本地玩家被释放（场景切换/换人/回菜单）时收起
	if _is_open:
		var coop = CoopNetScript.instance
		var p = coop.call("get_local_player") if coop != null and is_instance_valid(coop) else null
		if p == null or not is_instance_valid(p):
			_hide_now()


func _on_upgrade_begin() -> void:
	_upgrade_active = true


func _on_upgrade_end() -> void:
	_upgrade_active = false


# ---------------- 开合 ----------------

func _open_chat() -> void:
	var coop = CoopNetScript.instance
	if coop == null or not is_instance_valid(coop) or not bool(coop.is_lan_game):
		return
	_is_open = true
	_composing = true
	_hide_token += 1
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_panel.visible = true
	_panel.modulate.a = 1.0
	_set_peek_visual(false)
	_acquire_controls()
	_rebuild_log()
	_input_box.text = ""
	_input_box.grab_focus()
	SoundManager.play_sfx(SFX)


func _submit() -> void:
	if not _composing:
		return
	var text: String = _input_box.text
	_input_box.text = ""
	_input_box.release_focus()
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		coop.send_chat(text)
	SoundManager.play_sfx(SFX)
	# 发送即释放控件：鼠标立即恢复、玩家解除冻结（窗口仍按 2 秒淡出）
	_release_controls()
	_schedule_hide(HIDE_DELAY)


func _schedule_hide(delay: float) -> void:
	_hide_token += 1
	var token := _hide_token
	await get_tree().create_timer(delay).timeout
	if token != _hide_token or not _is_open:
		return
	_hide_now()


# 淡出期内再次激活 / PEEK 升格输入：取消淡出并重新聚焦输入（支持连续发送）。
func _refocus() -> void:
	_is_open = true
	_composing = true
	_hide_token += 1
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_panel.visible = true
	_panel.modulate.a = 1.0
	_set_peek_visual(false)
	_input_box.grab_focus()
	_acquire_controls()
	_scroll_to_bottom()
	SoundManager.play_sfx(SFX)


func _hide_now() -> void:
	if not _is_open:
		return
	_is_open = false
	_composing = false
	_hide_token += 1
	_release_controls()
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_panel, "modulate:a", 0.0, FADE_TIME)
	_fade_tween.tween_callback(func(): _panel.visible = false)


func _on_game_over(_player_dead: bool) -> void:
	# 游戏结束后保留聊天窗（不隐藏），新消息仍可自动显示（peek）
	_upgrade_active = false


# 自动显示（peek）：有新消息时展示，不聚焦、不占用控件、更透明，2 秒后淡出（新消息重置）。
func _peek_show() -> void:
	_is_open = true
	_composing = false
	_hide_token += 1
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_panel.visible = true
	_panel.modulate.a = 1.0
	_set_peek_visual(true)
	_rebuild_log()
	_schedule_hide(HIDE_DELAY)


# 输入态与 peek 态的视觉差异：只调面板背景与输入框，消息文字保持满不透明。
func _set_peek_visual(peek: bool) -> void:
	var sb := _panel.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		var flat := sb as StyleBoxFlat
		var col := flat.bg_color
		col.a = PEEK_BG_ALPHA if peek else _orig_bg_alpha
		flat.bg_color = col
	if _input_box != null and is_instance_valid(_input_box):
		_input_box.modulate.a = PEEK_INPUT_ALPHA if peek else 1.0


# ---------------- 控件占用 / 释放（鼠标 + 玩家冻结） ----------------

# 打开/重新聚焦时占用：显示鼠标、冻结本地玩家（幂等）。
func _acquire_controls() -> void:
	if _controls_held:
		return
	var coop = CoopNetScript.instance
	_frozen_player = null
	if coop != null and is_instance_valid(coop):
		var player = coop.call("get_local_player")
		if player != null and is_instance_valid(player):
			_frozen_player = player
	if _frozen_player != null:
		_prev_player_stop = bool(_frozen_player.get("player_stop"))
		_frozen_player.set("player_stop", true)
		var gun = _frozen_player.get("gun")
		if gun != null:
			gun.set("is_shoot", false)
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_controls_held = true


# 发送/隐藏时释放：恢复鼠标模式与玩家冻结状态（幂等）。
func _release_controls() -> void:
	if not _controls_held:
		return
	if _frozen_player != null and is_instance_valid(_frozen_player):
		_frozen_player.set("player_stop", _prev_player_stop)
	_frozen_player = null
	Input.mouse_mode = _prev_mouse_mode
	_controls_held = false


# ---------------- 日志 ----------------

func _rebuild_log() -> void:
	for c in _log_box.get_children():
		_log_box.remove_child(c)
		c.queue_free()
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		for entry in coop.get_chat_log():
			if entry is Dictionary:
				_add_line(str(entry.get("name", "")), str(entry.get("text", "")))
	_scroll_to_bottom()


func _on_chat_received(_peer_id: int, name: String, text: String) -> void:
	if not _is_open:
		# 关闭（含淡出中）时收到新消息 → 自动显示（peek）
		_peek_show()
		return
	_add_line(name, text)
	_scroll_to_bottom()
	if not _composing:
		# peek 期间收到新消息：重置 2 秒淡出计时
		_schedule_hide(HIDE_DELAY)


func _add_line(name: String, text: String) -> void:
	var label := Label.new()
	label.text = "%s： %s" % [name, text]
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0.06, 0.06, 0.06, 1))
	label.add_theme_constant_override("outline_size", 3)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_box.add_child(label)


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	if _scroll == null or not is_instance_valid(_scroll):
		return
	var bar := _scroll.get_v_scroll_bar()
	if bar != null:
		_scroll.scroll_vertical = int(bar.max_value)


# ---------------- 手机端开聊按钮 ----------------

func _ensure_button() -> void:
	var coop = CoopNetScript.instance
	var active: bool = coop != null and is_instance_valid(coop) and bool(coop.is_lan_game)
	if not active:
		if _btn != null and is_instance_valid(_btn):
			_btn.visible = false
		_hide_ping()
		return
	var player = coop.call("get_local_player")
	if player == null or not is_instance_valid(player):
		if _btn != null and is_instance_valid(_btn):
			_btn.visible = false
		_hide_ping()
		return
	var ammo_pos: Node = player.get_node_or_null("GameUI/AmmoPosition")
	if ammo_pos == null:
		if _btn != null and is_instance_valid(_btn):
			_btn.visible = false
		_hide_ping()
		return
	if _btn == null or not is_instance_valid(_btn):
		_btn = _make_button()
	if _btn.get_parent() != ammo_pos:
		if _btn.get_parent() != null:
			_btn.get_parent().remove_child(_btn)
		ammo_pos.add_child(_btn)
		_btn.position = BTN_POS
	_btn.visible = true
	# 延迟小字：按钮正下方
	if _ping_label == null or not is_instance_valid(_ping_label):
		_ping_label = _make_ping_label()
	if _ping_label.get_parent() != ammo_pos:
		if _ping_label.get_parent() != null:
			_ping_label.get_parent().remove_child(_ping_label)
		ammo_pos.add_child(_ping_label)
		_ping_label.position = PING_POS
	_ping_label.visible = true


func _make_button() -> TextureButton:
	var b := TextureButton.new()
	b.name = "CoopChatButton"
	b.texture_normal = BUTTON_ICON
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_SCALE
	b.custom_minimum_size = BTN_SIZE
	b.size = BTN_SIZE
	b.modulate = Color(1, 1, 1, 0.45)
	# 纯显示：不接收 GUI 鼠标事件，避免游玩期吞鼠标/误触；点击由 _input 命中判定。
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


# ---------------- 延迟小字 ----------------

func _make_ping_label() -> Label:
	var l := Label.new()
	l.name = "CoopChatPing"
	l.add_theme_font_override("font", PING_FONT)
	l.add_theme_font_size_override("font_size", PING_FONT_SIZE)
	l.add_theme_color_override("font_color", PING_COLOR_GOOD)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.06, 0.06, 1))
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text = "--"
	l.custom_minimum_size = PING_SIZE
	l.size = PING_SIZE
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _hide_ping() -> void:
	if _ping_label != null and is_instance_valid(_ping_label):
		_ping_label.visible = false


func _refresh_pings(delta: float) -> void:
	_ping_timer -= delta
	if _ping_timer > 0.0:
		return
	_ping_timer = PING_REFRESH
	var coop = CoopNetScript.instance
	if coop == null or not is_instance_valid(coop) or not bool(coop.is_lan_game):
		return
	var timing = coop.call("get_network_timing")
	var rtt: float = float(timing.get("rtt", 0.0)) if timing is Dictionary else 0.0
	var quality: String = str(coop.call("get_network_quality_debug_text"))
	_apply_ping_label(_ping_label, rtt, quality)
	_apply_ping_label(_upgrade_ping, rtt, quality)


func _apply_ping_label(label: Label, rtt: float, quality: String) -> void:
	if label == null or not is_instance_valid(label):
		return
	var text: String = "%dms" % int(round(rtt)) if rtt > 0.0 else "--"
	if label.text != text:
		label.text = text
	var col: Color = PING_COLOR_GOOD
	if quality == "fair":
		col = PING_COLOR_FAIR
	elif quality == "poor":
		col = PING_COLOR_POOR
	label.add_theme_color_override("font_color", col)


# 升级页按钮（场景节点，编辑器可调位置）：升级阶段 + LAN + 本地玩家有效时显示。
func _ensure_upgrade_button() -> void:
	if _upgrade_btn == null or not is_instance_valid(_upgrade_btn):
		return
	var coop = CoopNetScript.instance
	var active: bool = coop != null and is_instance_valid(coop) and bool(coop.is_lan_game)
	var show: bool = active and _upgrade_active
	if show:
		var player = coop.call("get_local_player")
		show = player != null and is_instance_valid(player)
	_upgrade_btn.visible = show
	if _upgrade_ping != null and is_instance_valid(_upgrade_ping):
		_upgrade_ping.visible = show


# 鼠标可点：聊天窗激活，或指针空闲（升级页/暂停等鼠标可见时）；游玩期鼠标被捕获(隐藏)则不点。
func _pointer_free() -> bool:
	return _is_open or Input.mouse_mode == Input.MOUSE_MODE_VISIBLE


# 命中判定：触摸始终可点；鼠标在指针空闲时可点（游玩期不处理、不 consume）。
func _button_hit(event: InputEvent) -> bool:
	return _hit_test(_btn, event) or _hit_test(_upgrade_btn, event)


func _hit_test(btn, event: InputEvent) -> bool:
	if btn == null or not is_instance_valid(btn) or not btn.visible:
		return false
	if event is InputEventScreenTouch:
		if not event.pressed:
			return false
		if not btn.get_global_rect().has_point(event.position):
			return false
		_last_touch_frame = Engine.get_process_frames()
		return true
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
			return false
		if not _pointer_free():
			return false
		if Engine.get_process_frames() - _last_touch_frame <= 1:
			return false  # 忽略触摸模拟出的鼠标事件
		return btn.get_global_rect().has_point(event.position)
	return false


func _activate() -> void:
	if not _is_open:
		_open_chat()
	elif _composing and _input_box.has_focus():
		_submit()
	else:
		# PEEK 或 COMPOSE 未聚焦（发送后淡出期）→ 升格/重新聚焦为输入态
		_refocus()


# 递归把控件及其后代设为不拦截鼠标（面板纯展示；输入靠程序聚焦）。
func _set_mouse_ignore(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in control.get_children():
		if c is Control:
			_set_mouse_ignore(c)
