extends Control

## 联机菜单覆盖层（option 菜单式布局：左侧 option_button 页签 + 右侧内容面板）。
## 页签复用 `res://ui/option_button.tscn`；颜色统一为绿色。通过 CoopNet.instance 管理连接。

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const MobileNoticeScene := preload("res://ui/mobile_notice.tscn")

enum CoopPanelMode { LAN, RELAY, DEDICATED, OPTION }

const TAB_GREEN := Color(0.0, 0.837, 0.295)

var on_coop: bool = false
var _selected_mode: int = CoopPanelMode.LAN
var _lan_status_message: String = "offline"
var on_lan: bool = false
var on_relay: bool = false
var nav_index: int = 0
var _player_id_notice: Node = null
var _active_tab: Node = null
var _room_list: VBoxContainer = null
var _room_keys: Array = []
var _browsing: bool = false

@onready var _panel: PanelContainer = $Panel
@onready var _ip_input: LineEdit = %IpInput
@onready var _join_button: Button = %JoinButton
@onready var _host_button: Button = %HostButton
@onready var _mode_subtitle_label: Label = %ModeSubtitleLabel
@onready var _dedicated_panel: VBoxContainer = %DedicatedPanel
@onready var _relay_server_input: LineEdit = %RelayServerInput
@onready var _relay_room_input: LineEdit = %RelayRoomInput
@onready var _relay_create_button: Button = %RelayCreateButton
@onready var _relay_join_button: Button = %RelayJoinButton
@onready var _saki_server_button: Button = %SakiServerButton
@onready var _relay_room_code_label: Label = %RelayRoomCodeLabel
@onready var _status_label: Label = %StatusLabel
@onready var _local_ip_label: Label = %LocalIpLabel
@onready var _status_dot: ColorRect = %StatusDot

@onready var _lan_panel: VBoxContainer = %LanPanel
@onready var _relay_panel: VBoxContainer = %RelayPanel
@onready var _option_panel: VBoxContainer = %OptionPanel
@onready var _player_id_input: LineEdit = %PlayerIdInput
@onready var _player_id_confirm: Button = %PlayerIdConfirm
@onready var _remote_effect_slider: HSlider = %RemoteEffectFreq
@onready var _remote_flash_slider: HSlider = %RemoteFlashFreq
@onready var _remote_text_slider: HSlider = %RemoteTextFreq
@onready var _remote_effect_value: Label = %RemoteEffectFreqValue
@onready var _remote_flash_value: Label = %RemoteFlashFreqValue
@onready var _remote_text_value: Label = %RemoteTextFreqValue
@onready var _debug_hud_toggle = %DebugHudToggle
@onready var lan: PanelContainer = %LAN
@onready var relay: PanelContainer = %Relay
@onready var option: PanelContainer = %Option
@onready var lan_option_player: AnimationPlayer = lan.get_node("AnimationPlayer")
@onready var relay_option_player: AnimationPlayer = relay.get_node("AnimationPlayer")
@onready var option_option_player: AnimationPlayer = option.get_node("AnimationPlayer")
@onready var panel_animator: AnimationPlayer = %PanelAnimator
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var _banner: TextureRect = %Banner


func _ready() -> void:
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_relay_create_button.pressed.connect(_on_relay_create_pressed)
	_relay_join_button.pressed.connect(_on_relay_join_pressed)
	_saki_server_button.pressed.connect(_on_saki_server_pressed)
	_host_button.gui_input.connect(_on_host_gui_input)
	_join_button.gui_input.connect(_on_join_gui_input)
	_ip_input.gui_input.connect(_on_ip_input_gui_input)
	_relay_server_input.gui_input.connect(_on_relay_server_input_gui_input)
	_relay_room_input.gui_input.connect(_on_relay_room_input_gui_input)
	_relay_create_button.gui_input.connect(_on_relay_create_gui_input)
	_relay_join_button.gui_input.connect(_on_relay_join_gui_input)

	# option_button 自身会 play("selected") 并 emit GameEvents.menu_button(button_id)
	GameEvents.menu_button.connect(_on_menu_button)

	var coop = CoopNetScript.instance
	if coop != null:
		coop.connection_status_changed.connect(_on_connection_status_changed)
		coop.character_select_requested.connect(out_coop_selected)
		coop.relay_room_created.connect(_on_relay_room_created)

	_apply_tab_color(lan)
	_apply_tab_color(relay)
	_apply_tab_color(option)
	_setup_tab_input(lan)
	_setup_tab_input(relay)
	_setup_tab_input(option)
	_setup_tabs_container()
	_load_banner_texture()
	_setup_return_button()
	animation_player.animation_finished.connect(_on_page_anim_finished)
	_remote_effect_slider.value_changed.connect(_on_remote_effect_value_changed)
	_remote_flash_slider.value_changed.connect(_on_remote_flash_value_changed)
	_remote_text_slider.value_changed.connect(_on_remote_text_value_changed)
	_debug_hud_toggle.toggled.connect(_on_debug_hud_toggled)
	_player_id_confirm.pressed.connect(_on_player_id_confirm_pressed)
	_player_id_input.text_submitted.connect(_on_player_id_text_submitted)
	_player_id_input.gui_input.connect(_on_player_id_input_gui_input)
	_player_id_confirm.gui_input.connect(_on_player_id_confirm_gui_input)
	_player_id_notice = MobileNoticeScene.instantiate()
	add_child(_player_id_notice)
	_refresh_option_sliders()
	_refresh_player_id_input()
	_build_room_list()

	visible = false
	panel_animator.play("panel_option_out")
	_update_local_ip_label()
	_select_mode(CoopPanelMode.LAN, false)
	_set_status("offline", "LAN")
	_set_buttons_enabled(false)


# ---------------- LAN 房间列表（UDP 发现） ----------------

func _build_room_list() -> void:
	if _lan_panel == null:
		return
	_room_list = VBoxContainer.new()
	_room_list.name = "RoomList"
	_room_list.add_theme_constant_override("separation", 2)
	_lan_panel.add_child(_room_list)
	var join_row := _lan_panel.get_node_or_null("JoinRow")
	if join_row != null:
		_lan_panel.move_child(_room_list, join_row.get_index() + 1)


func _process(_delta: float) -> void:
	var coop = CoopNetScript.instance
	var browsing: bool = visible and _selected_mode == CoopPanelMode.LAN \
			and (coop == null or not bool(coop.is_lan_game))
	if browsing != _browsing:
		_browsing = browsing
		if coop != null and is_instance_valid(coop):
			coop.call("browse_lan_start" if browsing else "browse_lan_stop")
		if not browsing and _room_list != null:
			for c in _room_list.get_children():
				c.queue_free()
			_room_keys = []
	if _browsing and coop != null and is_instance_valid(coop):
		_refresh_room_list(coop)


func _refresh_room_list(coop: Node) -> void:
	if _room_list == null:
		return
	var rooms: Array = coop.call("get_lan_rooms")
	var keys: Array = []
	for r in rooms:
		keys.append("%s:%d:%d" % [str(r.get("ip", "")), int(r.get("port", 0)), int(r.get("players", 0))])
	if keys == _room_keys:
		return
	_room_keys = keys
	for c in _room_list.get_children():
		c.queue_free()
	if rooms.is_empty():
		var lbl := Label.new()
		lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		lbl.text = tr("coop_lan_scanning")
		_room_list.add_child(lbl)
		return
	for r in rooms:
		var b := Button.new()
		b.text = "%s  %d/%d" % [str(r.get("name", "")), int(r.get("players", 0)), int(r.get("max", 0))]
		b.tooltip_text = "%s:%d" % [str(r.get("ip", "")), int(r.get("port", 0))]
		b.pressed.connect(_on_room_pressed.bind(str(r.get("ip", ""))))
		_room_list.add_child(b)


func _on_room_pressed(ip: String) -> void:
	_ip_input.text = ip
	_on_join_pressed()


func _apply_tab_color(tab: Node) -> void:
	var bar := tab.get_node_or_null("Node2D/ColorRect")
	if bar != null:
		bar.color = TAB_GREEN


# option_button 根为 MOUSE_FILTER_IGNORE，且未选中时内部高亮 ColorRect 宽度为 0，
# 因此未选中页签没有有效命中区。把整块页签根设为唯一命中目标（子节点全部 IGNORE），
# 从而恢复悬停（根自带 mouse_entered/exited）与点击（根 gui_input + shoot）。
func _setup_tab_input(tab: Node) -> void:
	tab.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in tab.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := tab.get_node_or_null("Node2D")
	if inner != null:
		for child in inner.get_children():
			if child is Control:
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _setup_tabs_container() -> void:
	var box := get_node_or_null("Node2D/VBoxContainer")
	if box is Control:
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _load_banner_texture() -> void:
	if _banner == null:
		return
	var bytes := FileAccess.get_file_as_bytes("res://mods/etn_coop/ui/coop_icon.png")
	if bytes.is_empty():
		return
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		return
	_banner.texture = ImageTexture.create_from_image(img)


func _setup_return_button() -> void:
	var ret := get_node_or_null("Node2D/return")
	if ret == null:
		return
	# 覆盖本体 return.gd 的 pause_press 行为：仅关闭本覆盖层
	var cb := Callable(ret, "_on_gui_input")
	if ret.gui_input.is_connected(cb):
		ret.gui_input.disconnect(cb)
	if not ret.pressed.is_connected(out_coop_selected):
		ret.pressed.connect(out_coop_selected)


func _on_page_anim_finished(anim_name: StringName) -> void:
	if anim_name == "coop_out" and not on_coop:
		visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not on_coop or not _is_gamepad_event(event):
		return
	if _is_ui_cancel(event):
		out_coop_selected()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_right"):
		_move_nav(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_left"):
		_move_nav(-1)
		get_viewport().set_input_as_handled()
	elif _is_ui_accept(event):
		_activate_nav()
		get_viewport().set_input_as_handled()


func _is_ui_accept(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_accept") or event.is_action_pressed("shoot")


func _is_ui_cancel(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")


func _is_gamepad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


func _get_nav_items() -> Array[Control]:
	var items: Array[Control] = [lan, relay, option]
	# 玩家 ID 行常驻顶部（所有页签通用）
	items.append(_player_id_input)
	items.append(_player_id_confirm)
	if _selected_mode == CoopPanelMode.LAN:
		items.append(_host_button)
		items.append(_ip_input)
		items.append(_join_button)
	elif _selected_mode == CoopPanelMode.RELAY:
		items.append(_relay_server_input)
		items.append(_relay_create_button)
		items.append(_saki_server_button)
		items.append(_relay_room_input)
		items.append(_relay_join_button)
	elif _selected_mode == CoopPanelMode.OPTION:
		items.append(_remote_effect_slider)
		items.append(_remote_flash_slider)
		items.append(_remote_text_slider)
	return items


func _move_nav(step: int) -> void:
	var items: Array[Control] = _get_nav_items()
	if items.is_empty():
		return
	_unfocus_nav(items[nav_index])
	nav_index = posmod(nav_index + step, items.size())
	_focus_nav(items[nav_index])


func _focus_nav(item: Control) -> void:
	if item == lan:
		mouse_on_lan()
	elif item == relay:
		mouse_on_relay()
	elif item == option:
		mouse_on_option()
	else:
		item.grab_focus()
		SoundManager.play_sfx("ButtonSounds2")


func _unfocus_nav(item: Control) -> void:
	if item == lan:
		mouse_out_lan()
	elif item == relay:
		mouse_out_relay()
	elif item == option:
		mouse_out_option()


func _activate_nav() -> void:
	var items: Array[Control] = _get_nav_items()
	if items.is_empty():
		return
	nav_index = clamp(nav_index, 0, items.size() - 1)
	var item: Control = items[nav_index]
	if item == lan:
		_set_selected_mode(CoopPanelMode.LAN)
		nav_index = 0
	elif item == relay:
		_set_selected_mode(CoopPanelMode.RELAY)
		nav_index = 1
	elif item == option:
		_set_selected_mode(CoopPanelMode.OPTION)
		nav_index = 2
	elif item is LineEdit:
		item.grab_focus()
		DisplayServer.virtual_keyboard_show(item.text)
	elif item is Button:
		item.emit_signal("pressed")


func on_coop_selected() -> void:
	on_coop = true
	visible = true
	if get_viewport() != null:
		get_viewport().gui_release_focus()
	_set_buttons_enabled(true)
	_play_in()
	nav_index = 0
	if Game.control_mode == 2 and not _get_nav_items().is_empty():
		_focus_nav(_get_nav_items()[nav_index])


func out_coop_selected() -> void:
	SoundManager.play_sfx("UISounds2")
	on_coop = false
	_set_buttons_enabled(false)
	_play_out()


func _set_buttons_enabled(enabled: bool) -> void:
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in _panel.find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var controls: Array[Control] = [
		_host_button, _join_button, _ip_input,
		_relay_server_input, _relay_room_input, _relay_create_button, _relay_join_button, _saki_server_button,
		option, _player_id_input, _player_id_confirm, _remote_effect_slider, _remote_flash_slider, _remote_text_slider,
		_debug_hud_toggle,
	]
	for c in controls:
		c.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE


func _play_in() -> void:
	animation_player.play("coop_in")


func _play_out() -> void:
	animation_player.play("coop_out")


func _on_host_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	_update_local_ip_label()
	var coop = CoopNetScript.instance
	# 开房成功后 CoopNet 自动进入准备房（测试房）
	if coop != null:
		coop.host_game()


func _on_join_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	var coop = CoopNetScript.instance
	if coop != null:
		coop.join_game(_ip_input.text)


func _select_mode(mode: int, play_sound: bool = true) -> void:
	_set_selected_mode(mode, play_sound)


func _set_selected_mode(mode: int, play_sound: bool = true) -> void:
	if play_sound:
		SoundManager.play_sfx("ButtonSounds")
	_selected_mode = mode
	on_lan = mode == CoopPanelMode.LAN
	on_relay = mode == CoopPanelMode.RELAY
	_lan_panel.visible = on_lan
	_relay_panel.visible = on_relay
	_dedicated_panel.visible = mode == CoopPanelMode.DEDICATED
	_option_panel.visible = mode == CoopPanelMode.OPTION
	match mode:
		CoopPanelMode.LAN:
			_mode_subtitle_label.text = "coop_mode_subtitle_lan"
			_set_status(_lan_status_message, "LAN")
		CoopPanelMode.RELAY:
			_mode_subtitle_label.text = "coop_mode_subtitle_relay"
			_set_status(_lan_status_message, "RELAY")
		CoopPanelMode.DEDICATED:
			_mode_subtitle_label.text = "coop_mode_subtitle_dedicated"
			_set_status("coop_status_dedicated_unavailable", "DEDICATED")
		CoopPanelMode.OPTION:
			_mode_subtitle_label.text = "coop_mode_subtitle_option"
			_set_status(_lan_status_message, "OPTION")
			_refresh_option_sliders()
	_update_mode_visuals(mode)


func _update_mode_visuals(mode: int) -> void:
	panel_animator.play("panel_option_out")
	var new_tab: Node = _tab_for_mode(mode)
	# 只收回「上一个选中」的页签；未被选中的页签不动（否则每次点击三个页签都会播收回）。
	if _active_tab != null and _active_tab != new_tab:
		_deselect_tab(_active_tab)
	_active_tab = new_tab
	if new_tab != null:
		new_tab.set("on_show", true)
		var tab_anim: AnimationPlayer = new_tab.get_node("AnimationPlayer")
		if tab_anim.current_animation != "selected":
			tab_anim.play("selected")
	panel_animator.play("panel_option_in")


func _tab_for_mode(mode: int) -> Node:
	match mode:
		CoopPanelMode.LAN:
			return lan
		CoopPanelMode.RELAY:
			return relay
		CoopPanelMode.OPTION:
			return option
	return null


func _deselect_tab(tab: Node) -> void:
	tab.set("on_show", false)
	tab.get_node("AnimationPlayer").play_backwards("on_select")


func _on_menu_button(button_id: String) -> void:
	if button_id == "coop_lan":
		if _selected_mode != CoopPanelMode.LAN:
			SoundManager.play_sfx("ButtonSounds")
			_set_selected_mode(CoopPanelMode.LAN, false)
	elif button_id == "coop_relay":
		if _selected_mode != CoopPanelMode.RELAY:
			SoundManager.play_sfx("ButtonSounds")
			_set_selected_mode(CoopPanelMode.RELAY, false)
	elif button_id == "coop_option":
		if _selected_mode != CoopPanelMode.OPTION:
			SoundManager.play_sfx("ButtonSounds")
			_set_selected_mode(CoopPanelMode.OPTION, false)


func _on_relay_create_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	var coop = CoopNetScript.instance
	if coop == null:
		return
	var result: String = str(coop.create_relay_room(_relay_server_input.text))
	if result == "":
		_relay_room_code_label.text = "coop_room_code_empty"
		return
	# 建房成功后 CoopNet 自动进入准备房（测试房）
	_relay_room_code_label.text = "coop_room_code_creating"


func _on_relay_room_created(room_code: String) -> void:
	_relay_room_code_label.text = tr("coop_room_code_value") % room_code


func _on_relay_join_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	var coop = CoopNetScript.instance
	if coop != null:
		coop.join_relay_room(_relay_server_input.text, _relay_room_input.text)


func _on_saki_server_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	_relay_server_input.text = "mc.yqst.top:32085"


func mouse_on_lan() -> void:
	if _selected_mode != CoopPanelMode.LAN:
		SoundManager.play_sfx("ButtonSounds2")
		lan_option_player.play("on_select")


func mouse_out_lan() -> void:
	if _selected_mode != CoopPanelMode.LAN:
		lan_option_player.play_backwards("on_select")


func mouse_on_relay() -> void:
	if _selected_mode != CoopPanelMode.RELAY:
		SoundManager.play_sfx("ButtonSounds2")
		relay_option_player.play("on_select")


func mouse_out_relay() -> void:
	if _selected_mode != CoopPanelMode.RELAY:
		relay_option_player.play_backwards("on_select")


func mouse_on_option() -> void:
	if _selected_mode != CoopPanelMode.OPTION:
		SoundManager.play_sfx("ButtonSounds2")
		option_option_player.play("on_select")


func mouse_out_option() -> void:
	if _selected_mode != CoopPanelMode.OPTION:
		option_option_player.play_backwards("on_select")


# ---------------- OPTION 页：其它玩家攻击特效频率 ----------------

func _coop_settings():
	var coop = CoopNetScript.instance
	if coop == null:
		return null
	return coop.settings


func _refresh_option_sliders() -> void:
	var s = _coop_settings()
	var ef: int = int(s.remote_effect_freq) if s != null else 4
	var ff: int = int(s.remote_flash_freq) if s != null else 4
	var tf: int = int(s.remote_text_freq) if s != null else 4
	_remote_effect_slider.set_value_no_signal(ef)
	_remote_flash_slider.set_value_no_signal(ff)
	_remote_text_slider.set_value_no_signal(tf)
	_remote_effect_value.text = _freq_value_text(ef)
	_remote_flash_value.text = _freq_value_text(ff)
	_remote_text_value.text = _freq_value_text(tf)
	var dh: bool = bool(s.debug_hud) if s != null else false
	var hud = get_tree().get_first_node_in_group("CoopNetDebugHud")
	if hud != null and is_instance_valid(hud):
		dh = bool(hud.visible)
	_debug_hud_toggle.call("set_on", dh, false)


func _on_debug_hud_toggled(on: bool) -> void:
	var s = _coop_settings()
	if s != null:
		s.apply_debug_hud(on)
	var hud = get_tree().get_first_node_in_group("CoopNetDebugHud")
	if hud != null and is_instance_valid(hud) and hud.has_method("set_shown"):
		hud.call("set_shown", on)


# ---------------- OPTION 页：玩家 ID ----------------

func _refresh_player_id_input() -> void:
	var coop = CoopNetScript.instance
	var name_text: String = ""
	if coop != null:
		var s = coop.get("settings")
		if s != null:
			name_text = str(s.get("player_id"))
	_player_id_input.text = name_text


func _on_player_id_confirm_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	_submit_player_id()


func _on_player_id_text_submitted(_text: String) -> void:
	_submit_player_id()


# 按「确定」/回车：>12 字符拒绝保存并提示；否则保存并提示已保存。
func _submit_player_id() -> void:
	var coop = CoopNetScript.instance
	if coop == null:
		return
	var ok: bool = bool(coop.call("set_local_display_name", _player_id_input.text))
	if _player_id_notice != null and is_instance_valid(_player_id_notice):
		_player_id_notice.call("notice", "coop_player_id_saved" if ok else "coop_player_id_too_long")


func _on_remote_effect_value_changed(value: float) -> void:
	var idx: int = clampi(int(round(value)), 0, 4)
	var s = _coop_settings()
	if s != null:
		s.apply_remote_effect(idx)
	_remote_effect_value.text = _freq_value_text(idx)


func _on_remote_flash_value_changed(value: float) -> void:
	var idx: int = clampi(int(round(value)), 0, 4)
	var s = _coop_settings()
	if s != null:
		s.apply_remote_flash(idx)
	_remote_flash_value.text = _freq_value_text(idx)


func _on_remote_text_value_changed(value: float) -> void:
	var idx: int = clampi(int(round(value)), 0, 4)
	var s = _coop_settings()
	if s != null:
		s.apply_remote_text(idx)
	_remote_text_value.text = _freq_value_text(idx)


func _freq_value_text(idx: int) -> String:
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


func _on_player_id_input_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_player_id_input.grab_focus()
		DisplayServer.virtual_keyboard_show(_player_id_input.text)
		_player_id_input.accept_event()


func _on_player_id_confirm_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_on_player_id_confirm_pressed()
		_player_id_confirm.accept_event()


func _on_host_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_on_host_pressed()
		_host_button.accept_event()


func _on_join_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_on_join_pressed()
		_join_button.accept_event()


func _on_ip_input_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_ip_input.grab_focus()
		DisplayServer.virtual_keyboard_show(_ip_input.text)
		_ip_input.accept_event()


func _on_relay_server_input_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_relay_server_input.grab_focus()
		DisplayServer.virtual_keyboard_show(_relay_server_input.text)
		_relay_server_input.accept_event()


func _on_relay_room_input_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_relay_room_input.grab_focus()
		DisplayServer.virtual_keyboard_show(_relay_room_input.text)
		_relay_room_input.accept_event()


func _on_relay_create_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_on_relay_create_pressed()
		_relay_create_button.accept_event()


func _on_relay_join_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_on_relay_join_pressed()
		_relay_join_button.accept_event()


func _on_connection_status_changed(message: String) -> void:
	if _selected_mode == CoopPanelMode.RELAY:
		_set_status(message, "RELAY")
	elif _selected_mode == CoopPanelMode.DEDICATED:
		return
	else:
		_lan_status_message = message
		_set_status(message, "LAN")
	var coop = CoopNetScript.instance
	if coop != null and coop.relay_room_code != "":
		_relay_room_code_label.text = tr("coop_room_code_value") % coop.relay_room_code
	if message.begins_with("Hosting"):
		_update_local_ip_label(message)


func _set_status(message: String, prefix: String = "LAN") -> void:
	if _status_label != null:
		_status_label.text = tr("coop_status_format") % [_localize_status_prefix(prefix), _localize_status_message(message)]
	if _status_dot == null:
		return
	var lower := message.to_lower()
	if lower.contains("failed") or lower.contains("disconnected") or lower.contains("not available"):
		_status_dot.color = Color(0.95, 0.18, 0.12)
	elif lower.contains("connected") or lower.contains("joined") or lower.contains("selected") or lower.contains("created"):
		_status_dot.color = Color(0.2, 0.9, 0.35)
	elif lower.contains("hosting") or lower.contains("joining") or lower.contains("waiting") or lower.contains("creating"):
		_status_dot.color = Color(1.0, 0.78, 0.12)
	else:
		_status_dot.color = Color(0.45, 0.45, 0.45)


func _update_local_ip_label(host_message: String = "") -> void:
	if _local_ip_label == null:
		return
	var address_text := host_message
	if address_text.begins_with("Hosting "):
		address_text = address_text.trim_prefix("Hosting ")
	var displayed := address_text if address_text != "" else _get_local_ip_summary()
	_local_ip_label.text = tr("coop_your_ip_format") % displayed


func _get_local_ip_summary() -> String:
	var addresses: Array[String] = []
	for address in IP.get_local_addresses():
		if address.contains(":"):
			continue
		if address == "127.0.0.1" or address == "0.0.0.0":
			continue
		if address.begins_with("169.254."):
			continue
		addresses.append(address)
	return ", ".join(addresses) if not addresses.is_empty() else tr("coop_unavailable")


func _localize_status_prefix(prefix: String) -> String:
	match prefix:
		"LAN":
			return tr("coop_mode_lan")
		"RELAY":
			return tr("coop_mode_relay")
		"DEDICATED":
			return tr("coop_mode_dedicated")
		_:
			return prefix


func _localize_status_message(message: String) -> String:
	if message.begins_with("coop_status_"):
		return tr(message)
	var exact := {
		"offline": "coop_status_offline",
		"Host failed": "coop_status_host_failed",
		"Join failed": "coop_status_join_failed",
		"Creating relay room": "coop_status_creating_relay_room",
		"Only host can start a LAN run": "coop_status_only_host_start",
		"Waiting for all players to select": "coop_status_waiting_for_players",
		"Connected to relay": "coop_status_connected_relay",
		"Connected to host": "coop_status_connected_host",
		"Connection failed": "coop_status_connection_failed",
		"Relay disconnected": "coop_status_relay_disconnected",
		"Server disconnected": "coop_status_server_disconnected",
	}
	if exact.has(message):
		return tr(exact[message])
	if message.begins_with("Relay room ") and message.ends_with(" created"):
		return tr("coop_status_relay_room_created") % message.trim_prefix("Relay room ").trim_suffix(" created")
	if message.begins_with("Peer ") and message.ends_with(" joined"):
		return tr("coop_status_peer_joined") % message.trim_prefix("Peer ").trim_suffix(" joined")
	if message.begins_with("Peer ") and message.ends_with(" left"):
		return tr("coop_status_peer_left") % message.trim_prefix("Peer ").trim_suffix(" left")
	var prefixes := {
		"Host failed: ": "coop_status_host_failed_detail",
		"Join failed: ": "coop_status_join_failed_detail",
		"Hosting LAN on port ": "coop_status_hosting_lan_port",
		"Hosting ": "coop_status_hosting_address",
		"Joining relay room ": "coop_status_joining_relay_room",
		"Joining ": "coop_status_joining_address",
		"Joined relay as peer ": "coop_status_joined_relay_peer",
		"Relay failed: ": "coop_status_relay_failed_detail",
	}
	for source_prefix in prefixes:
		if message.begins_with(source_prefix):
			return tr(prefixes[source_prefix]) % message.trim_prefix(source_prefix)
	return message
