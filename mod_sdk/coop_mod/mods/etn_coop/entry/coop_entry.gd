extends Node

## etn_coop 入口：由 ModManager 在启动时实例化（mod.json.entry）。
## 职责：安装本地化 → 创建 CoopNet 常驻节点 → 注册 ExtensionHooks → 注入主菜单 COOP 按钮与覆盖层 → 调试热键。
## 注意：mod 脚本不能用 class_name 全局名互引（pck 不含全局类缓存），一律 preload。

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const CoopFlowScript := preload("res://mods/etn_coop/net/coop_flow.gd")
const RoomLabelScript := preload("res://mods/etn_coop/ui/coop_room_label.gd")
const CoopMenuScene := preload("res://mods/etn_coop/ui/coop_menu.tscn")
const NetDebugHudScript := preload("res://mods/etn_coop/ui/net_debug_hud.gd")
const ScoreboardScene := preload("res://mods/etn_coop/ui/coop_scoreboard.tscn")
const ChatScene := preload("res://mods/etn_coop/ui/coop_chat.tscn")
const MenuButtonScene := preload("res://ui/menu_button.tscn")
const CoopI18n := preload("res://mods/etn_coop/i18n/coop_i18n.gd")
const MENU_FONT := preload("res://fonts/BoutiqueBitmap9x9_1.9.ttf")

var _coop = null
var _overlay = null
var _menu_canvas = null
var _hud: Node = null
var _scoreboard: Node = null
var _chat: Node = null
var _flow: Node = null
var _room_label: Node = null


func _ready() -> void:
	CoopI18n.install()
	_coop = CoopNetScript.new()
	_coop.name = "CoopNet"
	add_child(_coop)
	CoopNetScript.instance = _coop
	_coop.call("install_hooks")
	_flow = CoopFlowScript.new()
	_flow.name = "CoopFlow"
	add_child(_flow)
	_room_label = RoomLabelScript.new()
	_room_label.name = "CoopRoomLabel"
	get_tree().root.add_child(_room_label)
	_hud = NetDebugHudScript.new()
	_hud.name = "CoopNetDebugHud"
	_hud.add_to_group("CoopNetDebugHud")
	get_tree().root.add_child(_hud)
	if _coop.settings.debug_hud:
		_hud.call("set_shown", true)
	_scoreboard = ScoreboardScene.instantiate()
	get_tree().root.add_child(_scoreboard)
	_chat = ChatScene.instantiate()
	_chat.name = "CoopChat"
	get_tree().root.add_child(_chat)
	ExtensionHooks.populate_menu_buttons = Callable(self, "_populate_menu_buttons")
	GameEvents.menu_button.connect(_on_menu_button)
	_coop.get("character_select_requested").connect(_on_character_select_requested)
	print("[etn_coop] entry ready: hooks installed; F9 net HUD / F10 host / F11 join 127.0.0.1 / F12 leave")
	_handle_dev_args()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		if _hud != null and is_instance_valid(_hud):
			_hud.call("toggle")
			get_viewport().set_input_as_handled()


# 主菜单注入 COOP 按钮（经 ExtensionHooks.populate_menu_buttons），置于 Quit 之上
func _populate_menu_buttons(box: Node) -> void:
	if box == null:
		return
	_menu_canvas = _find_canvas_layer(box)
	var btn = MenuButtonScene.instantiate()
	btn.set("button_id", "coop")

	var label := Label.new()
	label.name = "coop"
	label.text = "COOP"
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_override("font", MENU_FONT)
	label.add_theme_font_size_override("font_size", 19)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_constant_override("shadow_outline_size", 3)
	label.add_theme_constant_override("shadow_offset_x", -1)
	label.add_theme_constant_override("shadow_offset_y", 3)
	btn.add_child(label)

	box.add_child(btn)

	# 让 COOP 恰好位于 Quit 之上（扫描 button_id，避免硬编码索引）
	var quit_index: int = box.get_child_count() - 1
	for i in box.get_child_count():
		var c: Node = box.get_child(i)
		if c.get("button_id") == "game_quit":
			quit_index = i
			break
	box.move_child(btn, quit_index)
	if quit_index > 0:
		btn.focus_neighbor_top = btn.get_path_to(box.get_child(quit_index - 1))
	if quit_index + 1 < box.get_child_count():
		btn.focus_neighbor_bottom = btn.get_path_to(box.get_child(quit_index + 1))


func _find_canvas_layer(node: Node) -> CanvasLayer:
	var n: Node = node
	while n != null:
		if n is CanvasLayer:
			return n
		n = n.get_parent()
	return null


func _on_menu_button(button_id: String) -> void:
	if button_id == "coop":
		_open_overlay()


func _open_overlay() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		_overlay = CoopMenuScene.instantiate()
		var parent: Node = _menu_canvas if _menu_canvas != null else get_tree().root
		parent.add_child(_overlay)
	_overlay.call("on_coop_selected")


func _on_character_select_requested() -> void:
	if _overlay != null and is_instance_valid(_overlay) and _overlay.get("on_coop"):
		_overlay.call("out_coop_selected")
	GameEvents.emit_menu_button("new_game")


# 无头压测：N 秒后优雅退出（刷新 stdout，供回归脚本采集完整 sim-report）
func _auto_quit_after(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
	print("[etn_coop] dev auto-quit after %.0fs" % sec)
	get_tree().quit()


# 开发/无头自测：--coop-host / --coop-join=<ip> [--coop-devbattle] [--coop-devenemy]
func _handle_dev_args() -> void:
	var mode := ""
	var target := ""
	var devbattle := false
	var devenemy := false
	var devhit := false
	var devbullet := false
	var deveffect := false
	var devcoin := false
	var devsummon := false
	var devdown := false
	var devbossevent := false
	var devlaser := false
	var devselflaser := false
	var devreset := false
	var devpause := false
	var devpreplaced := false
	var devfollow := false
	var devbuff := false
	var devowner := false
	var devring := false
	var devmenu := false
	var devhud := false
	var devitems := false
	var devspawn := false
	var devcharevent := false
	var devmotion := false
	var devconvert := false
	var devpart := false
	var devparthost := false
	var devpartlate := false
	var devrejoin := false
	var devscale := false
	var devfollows := false
	var devname := false
	var devhp := false
	var devhostdrop := false
	var devnetlag: float = 0.0
	var devsim: String = ""
	var devsimreport := false
	var devautoquit: float = 0.0
	var devsnapbatch: int = 0
	var devdiscover := false
	var devbadver := false
	var devflow := false
	var devabort := false
	var devready := false
	var devchat := false
	var use_relay := false
	var relay_target := ""
	for a in OS.get_cmdline_user_args():
		if a == "--coop-host":
			mode = "host"
		elif a.begins_with("--coop-join="):
			mode = "join"
			target = a.substr("--coop-join=".length())
		elif a.begins_with("--coop-relay-host="):
			mode = "host"
			use_relay = true
			relay_target = a.substr("--coop-relay-host=".length())
		elif a.begins_with("--coop-relay-join="):
			mode = "join"
			use_relay = true
			relay_target = a.substr("--coop-relay-join=".length())
		elif a == "--coop-devbattle":
			devbattle = true
		elif a == "--coop-devenemy":
			devenemy = true
		elif a == "--coop-devhit":
			devhit = true
		elif a == "--coop-devbullet":
			devbullet = true
		elif a == "--coop-deveffect":
			deveffect = true
		elif a == "--coop-devcoin":
			devcoin = true
		elif a == "--coop-devsummon":
			devsummon = true
		elif a == "--coop-devdown":
			devdown = true
		elif a == "--coop-devbossevent":
			devbossevent = true
		elif a == "--coop-devlaser":
			devlaser = true
		elif a == "--coop-devselflaser":
			devselflaser = true
		elif a == "--coop-devreset":
			devreset = true
		elif a == "--coop-devpause":
			devpause = true
		elif a == "--coop-devpreplaced":
			devpreplaced = true
		elif a == "--coop-devfollow":
			devfollow = true
		elif a == "--coop-devbuff":
			devbuff = true
		elif a == "--coop-devowner":
			devowner = true
		elif a == "--coop-devring":
			devring = true
		elif a == "--coop-devmenu":
			devmenu = true
		elif a == "--coop-devhud":
			devhud = true
		elif a == "--coop-devitems":
			devitems = true
		elif a == "--coop-devspawn":
			devspawn = true
		elif a == "--coop-devcharevent":
			devcharevent = true
		elif a == "--coop-devmotion":
			devmotion = true
		elif a == "--coop-devconvert":
			devconvert = true
		elif a == "--coop-devpart":
			devpart = true
		elif a == "--coop-devparthost":
			devparthost = true
		elif a == "--coop-devpartlate":
			devpartlate = true
		elif a == "--coop-devrejoin":
			devrejoin = true
		elif a == "--coop-devscale":
			devscale = true
		elif a == "--coop-devfollows":
			devfollows = true
		elif a == "--coop-devname":
			devname = true
		elif a == "--coop-devhp":
			devhp = true
		elif a == "--coop-devhostdrop":
			devhostdrop = true
		elif a.begins_with("--coop-devnetlag="):
			devnetlag = float(a.substr("--coop-devnetlag=".length()))
		elif a.begins_with("--coop-devsim="):
			devsim = a.substr("--coop-devsim=".length())
		elif a == "--coop-devsimreport":
			devsimreport = true
		elif a.begins_with("--coop-devautoquit="):
			devautoquit = float(a.substr("--coop-devautoquit=".length()))
		elif a.begins_with("--coop-devsnapbatch="):
			devsnapbatch = int(a.substr("--coop-devsnapbatch=".length()))
		elif a == "--coop-devdiscover":
			devdiscover = true
		elif a == "--coop-devbadver":
			devbadver = true
		elif a == "--coop-devflow":
			devflow = true
		elif a == "--coop-devabort":
			devabort = true
		elif a == "--coop-devready":
			devready = true
		elif a == "--coop-devchat":
			devchat = true
	# 旧的无头自测自行切换场景，禁用开房自动进准备房，避免重复切场景
	if devbattle:
		_coop.set("auto_enter_lobby", false)
	# 压测网络模拟：--coop-devsim=lat=100,jit=30,loss=10（任意子集）；--coop-devsimreport 周期上报指标
	if devsim != "":
		for kv in devsim.split(",", false):
			var parts := kv.split("=", false)
			if parts.size() != 2:
				continue
			match parts[0].strip_edges():
				"lat": _coop.sim_latency_ms = float(parts[1])
				"jit": _coop.sim_jitter_ms = float(parts[1])
				"loss": _coop.sim_loss_pct = float(parts[1])
	if devnetlag > 0.0:
		_coop.sim_loss_pct = devnetlag
	if devsnapbatch > 0:
		_coop.enemy_snapshot_batch_limit = devsnapbatch
	if devsim != "" or devnetlag > 0.0 or devsimreport:
		_coop.sim_report_enabled = true
	print("[etn_coop] dev net-sim lat=%.0f jit=%.0f loss=%.0f report=%s" % [_coop.sim_latency_ms, _coop.sim_jitter_ms, _coop.sim_loss_pct, str(_coop.sim_report_enabled)])
	if devbadver:
		_coop.dev_fake_game_version = "v0.0.0-fake"
		print("[etn_coop] dev bad version enabled")
	if devdiscover:
		_coop.call("browse_lan_start")
		await get_tree().create_timer(3.5).timeout
		print("[etn_coop] dev-discover rooms=%d %s" % [int(_coop.call("dev_lan_rooms")), str(_coop.call("get_lan_rooms"))])
		_coop.call("browse_lan_stop")
		get_tree().quit()
		return
	if devautoquit > 0.0:
		_auto_quit_after(devautoquit)
	if devmenu:
		_open_overlay()
		await get_tree().process_frame
		await get_tree().process_frame
		var ov = _overlay
		if ov == null:
			print("[etn_coop] dev-menu: overlay null")
		else:
			var has_panel: bool = ov.get_node_or_null("%OptionPanel") != null
			var has_eff: bool = ov.get_node_or_null("%RemoteEffectFreq") != null
			var has_flash: bool = ov.get_node_or_null("%RemoteFlashFreq") != null
			var has_text: bool = ov.get_node_or_null("%RemoteTextFreq") != null
			print("[etn_coop] dev-menu nodes: panel=%s eff=%s flash=%s text=%s" % [str(has_panel), str(has_eff), str(has_flash), str(has_text)])
			var pid_input = ov.get_node_or_null("%PlayerIdInput")
			var pid_confirm = ov.get_node_or_null("%PlayerIdConfirm")
			var pid_parent: String = str(pid_input.get_parent().name) if pid_input != null else "<none>"
			var lan_tab = ov.get_node_or_null("%LAN")
			var relay_tab = ov.get_node_or_null("%Relay")
			var option_tab = ov.get_node_or_null("%Option")
			var lan_ap: AnimationPlayer = lan_tab.get_node("AnimationPlayer")
			var relay_ap: AnimationPlayer = relay_tab.get_node("AnimationPlayer")
			var option_ap: AnimationPlayer = option_tab.get_node("AnimationPlayer")
			var relay_before: String = str(relay_ap.current_animation)
			ov.call("_set_selected_mode", 3)
			await get_tree().process_frame
			var opt_vis: bool = pid_input != null and pid_input.is_visible_in_tree()
			print("[etn_coop] dev-menu anim LAN->OPT: lan=%s relay=%s option=%s (expect on_select/untouched/selected); relay_before=%s" % [str(lan_ap.current_animation), str(relay_ap.current_animation), str(option_ap.current_animation), relay_before])
			ov.call("_set_selected_mode", 0)
			await get_tree().process_frame
			var lan_vis: bool = pid_input != null and pid_input.is_visible_in_tree()
			print("[etn_coop] dev-menu anim OPT->LAN: lan=%s relay=%s option=%s (expect selected/untouched/on_select)" % [str(lan_ap.current_animation), str(relay_ap.current_animation), str(option_ap.current_animation)])
			print("[etn_coop] dev-menu pid input=%s confirm=%s parent=%s opt_vis=%s lan_vis=%s" % [str(pid_input != null), str(pid_confirm != null), pid_parent, str(opt_vis), str(lan_vis)])
			ov.call("_set_selected_mode", 3)
			await get_tree().process_frame
			print("[etn_coop] dev-menu mode=%d" % int(ov.get("_selected_mode")))
		get_tree().quit()
		return
	if mode == "":
		return
	# 等主场景加载稳定再开服/加入（否则在 autoload _ready 内 change_scene 会丢 first_round_add）
	await get_tree().create_timer(1.0).timeout
	if use_relay:
		if mode == "host":
			_coop.call("create_relay_room", relay_target)
		else:
			var parts: Array = relay_target.split("|", false)
			var rurl: String = str(parts[0]) if parts.size() > 0 else relay_target
			var rcode: String = str(parts[1]) if parts.size() > 1 else ""
			_coop.call("join_relay_room", rurl, rcode)
	else:
		if mode == "host":
			_coop.call("host_game")
		else:
			_coop.call("join_game", target)
	if devbattle:
		var change_delay: float = 6.0 if mode == "host" else 1.5
		await get_tree().create_timer(change_delay).timeout
		GameEvents.change_scene("res://scenes/main/test_room.tscn", "res://scenes/player/momoi/momoi.tscn")
		await get_tree().create_timer(0.5).timeout
		if mode == "host" and devhostdrop:
			await get_tree().create_timer(3.0).timeout
			print("[etn_coop] dev-host-drop: closing connection and quitting")
			_coop.call("close_connection", true)
			get_tree().quit()
			return
		if devenemy and mode == "host":
			_coop.call("register_existing_enemies")
			print("[etn_coop] dev registered %d enemies" % _coop.enemy_by_net_id.size())
		if mode == "host" and devcoin:
			await get_tree().create_timer(2.5).timeout
			_coop.call("dev_spawn_coin", 100)
			print("[etn_coop] dev host spawned coin 100")
		if mode == "host" and devbossevent:
			for i in 3:
				_coop.call("dev_emit_boss_event")
				await get_tree().create_timer(0.3).timeout
			print("[etn_coop] dev host emitted 3 boss events")
		if mode == "host" and devselflaser:
			await get_tree().create_timer(1.0).timeout
			var h0: int = int(_coop.call("dev_local_hp"))
			_coop.call("dev_spawn_visual_laser_on_self")
			await get_tree().create_timer(2.5).timeout
			var h1: int = int(_coop.call("dev_local_hp"))
			print("[etn_coop] dev self-laser hp before=%d after=%d" % [h0, h1])
		if mode == "join":
			var waited: float = 0.0
			while not _coop.battle_active and waited < 15.0:
				await get_tree().create_timer(0.2).timeout
				waited += 0.2
			await get_tree().create_timer(0.5).timeout
			var before: int = int(_coop.call("dev_enemy_hp", 1))
			if devhit:
				_coop.call("dev_hit_enemy", 1, 30)
				await get_tree().create_timer(1.0).timeout
			var after: int = int(_coop.call("dev_enemy_hp", 1))
			print("[etn_coop] dev enemy#1 hp before=%d after=%d" % [before, after])
			if devbullet:
				for i in 5:
					_coop.call("dev_spawn_bullet")
					await get_tree().create_timer(0.3).timeout
				print("[etn_coop] dev spawned 5 bullets")
			if deveffect:
				for i in 3:
					_coop.call("dev_spawn_effect")
					await get_tree().create_timer(0.3).timeout
				print("[etn_coop] dev spawned 3 effects")
			if devcoin:
				await get_tree().create_timer(1.0).timeout
				var cbefore: int = int(_coop.call("dev_player_coins"))
				_coop.call("dev_pickup_coin")
				await get_tree().create_timer(1.0).timeout
				var cafter: int = int(_coop.call("dev_player_coins"))
				print("[etn_coop] dev coins before=%d after=%d" % [cbefore, cafter])
			if devsummon:
				_coop.call("dev_spawn_summoned")
				await get_tree().create_timer(1.0).timeout
				print("[etn_coop] dev spawned summon")
			if devlaser:
				_coop.call("dev_spawn_laser")
				await get_tree().create_timer(1.0).timeout
				print("[etn_coop] dev spawned laser")
			if devdown:
				await get_tree().create_timer(1.0).timeout
				_coop.call("dev_set_local_hp", 0)
				await get_tree().create_timer(0.8).timeout
				print("[etn_coop] dev local downed=%s" % str(_coop.call("dev_local_downed")))
	if devpause:
		await get_tree().create_timer(1.0).timeout
		_coop.call("dev_pause_probe")
		await get_tree().create_timer(1.5).timeout
	if devpreplaced:
		if mode == "host":
			await get_tree().create_timer(3.0).timeout
			print("[etn_coop] dev-preplaced host before: count=%d hp#0=%d" % [int(_coop.call("dev_preplaced_count")), int(_coop.call("dev_preplaced_hp", 0))])
			await get_tree().create_timer(6.0).timeout
			print("[etn_coop] dev-preplaced host after: count=%d hp#0=%d" % [int(_coop.call("dev_preplaced_count")), int(_coop.call("dev_preplaced_hp", 0))])
		else:
			await get_tree().create_timer(6.0).timeout
			print("[etn_coop] dev-preplaced client before: count=%d hp#0=%d" % [int(_coop.call("dev_preplaced_count")), int(_coop.call("dev_preplaced_hp", 0))])
			_coop.call("dev_damage_preplaced", 0, 999)
			await get_tree().create_timer(3.0).timeout
			print("[etn_coop] dev-preplaced client after: count=%d hp#0=%d" % [int(_coop.call("dev_preplaced_count")), int(_coop.call("dev_preplaced_hp", 0))])
	if devfollow:
		await get_tree().create_timer(2.0).timeout
		_coop.call("dev_follow_check")
	if devbuff:
		if mode == "host":
			await get_tree().create_timer(3.0).timeout
			_coop.call("dev_buff_state", 0)
			_coop.call("dev_apply_poison", 0)
			await get_tree().create_timer(5.0).timeout
			_coop.call("dev_buff_state", 0)
		else:
			await get_tree().create_timer(3.0).timeout
			_coop.call("dev_buff_state", 0)
			_coop.call("dev_apply_poison", 0)
			await get_tree().create_timer(5.0).timeout
			_coop.call("dev_buff_state", 0)
	if devowner:
		if mode == "host":
			await get_tree().create_timer(3.0).timeout
			_coop.call("dev_proc_state", "host-before")
			await get_tree().create_timer(4.0).timeout
			_coop.call("dev_proc_state", "host-after")
		else:
			await get_tree().create_timer(3.0).timeout
			_coop.call("dev_proc_state", "client-before")
			_coop.call("dev_damage_preplaced", 0, 10)
			await get_tree().create_timer(4.0).timeout
			_coop.call("dev_proc_state", "client-after")
	if devring:
		if mode == "host":
			await get_tree().create_timer(3.0).timeout
			_coop.call("dev_buff_state", 0)
			await get_tree().create_timer(4.0).timeout
			_coop.call("dev_buff_state", 0)
		else:
			await get_tree().create_timer(3.0).timeout
			_coop.call("dev_spawn_ring", 0)
			await get_tree().create_timer(4.0).timeout
			_coop.call("dev_buff_state", 0)
	if devreset:
		await get_tree().create_timer(1.0).timeout
		print("[etn_coop] dev triggering test_room_reset (mirrors before=%d)" % _coop.player_by_peer_id.size())
		GameEvents.emit_test_room_reset()
		await get_tree().create_timer(1.5).timeout
		print("[etn_coop] dev after-reset remotes=%d enemies=%d" % [_coop.player_by_peer_id.size(), _coop.enemy_by_net_id.size()])
	if devitems:
		var waited_items: float = 0.0
		while not _coop.battle_active and waited_items < 15.0:
			await get_tree().create_timer(0.2).timeout
			waited_items += 0.2
		await get_tree().create_timer(1.0).timeout
		for item_id in ["black_ninpero", "cowboy_hat", "sniper_scope", "suppressor", "cathedral_candle", "kitchen_knife", "little_kei", "utaha_turret", "shiroko_drone"]:
			_coop.call("dev_grant_item", item_id)
			await get_tree().create_timer(0.5).timeout
		print("[etn_coop] dev-items granted")
	if devspawn and mode == "host":
		var waited_spawn: float = 0.0
		while not _coop.battle_active and waited_spawn < 15.0:
			await get_tree().create_timer(0.2).timeout
			waited_spawn += 0.2
		await get_tree().create_timer(1.5).timeout
		_coop.call("dev_spawn_real_enemy")
		await get_tree().create_timer(3.0).timeout
		_coop.call("dev_enemy_targets")
	if devpart:
		var waited_pt: float = 0.0
		while not _coop.battle_active and waited_pt < 15.0:
			await get_tree().create_timer(0.2).timeout
			waited_pt += 0.2
		await get_tree().create_timer(1.5).timeout
		if mode == "host":
			var pid: int = int(_coop.call("dev_spawn_part_enemy"))
			await get_tree().create_timer(2.5).timeout
			print("[etn_coop] dev-part host net=%d part0=%d" % [pid, int(_coop.call("dev_enemy_part_hp", pid, 0))])
			await get_tree().create_timer(3.5).timeout
			print("[etn_coop] dev-part host settled net=%d part0=%d root=%d" % [pid, int(_coop.call("dev_enemy_part_hp", pid, 0)), int(_coop.call("dev_enemy_hp", pid))])
		else:
			var pid: int = int(_coop.call("dev_first_enemy_net_id"))
			var pb: int = int(_coop.call("dev_enemy_part_hp", pid, 0))
			_coop.call("dev_hit_enemy_part", pid, 0, 50)
			await get_tree().create_timer(1.0).timeout
			var pa: int = int(_coop.call("dev_enemy_part_hp", pid, 0))
			var rb: int = int(_coop.call("dev_enemy_hp", pid))
			_coop.call("dev_hit_enemy", pid, 30)
			await get_tree().create_timer(2.5).timeout
			var ps: int = int(_coop.call("dev_enemy_part_hp", pid, 0))
			var ra: int = int(_coop.call("dev_enemy_hp", pid))
			print("[etn_coop] dev-part client net=%d part0 before=%d after=%d settled=%d root before=%d after=%d" % [pid, pb, pa, ps, rb, ra])
	if devparthost:
		var waited_ph: float = 0.0
		while not _coop.battle_active and waited_ph < 15.0:
			await get_tree().create_timer(0.2).timeout
			waited_ph += 0.2
		await get_tree().create_timer(1.5).timeout
		if mode == "host":
			var pid: int = int(_coop.call("dev_spawn_part_enemy"))
			await get_tree().create_timer(3.0).timeout
			print("[etn_coop] dev-part-host host net=%d init=%d" % [pid, int(_coop.call("dev_enemy_part_hp", pid, 0))])
			_coop.call("dev_hit_enemy_part", pid, 0, 50)
			await get_tree().create_timer(1.0).timeout
			print("[etn_coop] dev-part-host host after=%d" % int(_coop.call("dev_enemy_part_hp", pid, 0)))
			await get_tree().create_timer(6.0).timeout
			print("[etn_coop] dev-part-host host settled=%d root=%d" % [int(_coop.call("dev_enemy_part_hp", pid, 0)), int(_coop.call("dev_enemy_hp", pid))])
		else:
			var pid: int = int(_coop.call("dev_first_enemy_net_id"))
			await get_tree().create_timer(2.0).timeout
			var p0: int = int(_coop.call("dev_enemy_part_hp", pid, 0))
			var s0 = _coop.call("dev_part_stats")
			await get_tree().create_timer(10.0).timeout
			var p1: int = int(_coop.call("dev_enemy_part_hp", pid, 0))
			var s1 = _coop.call("dev_part_stats")
			print("[etn_coop] dev-part-host client net=%d early=%d late=%d stats_early=%s stats_late=%s" % [pid, p0, p1, str(s0), str(s1)])
	if devpartlate:
		var waited_pl: float = 0.0
		while not _coop.battle_active and waited_pl < 15.0:
			await get_tree().create_timer(0.2).timeout
			waited_pl += 0.2
		if mode == "host":
			await get_tree().create_timer(1.5).timeout
			var pid: int = int(_coop.call("dev_spawn_part_enemy"))
			await get_tree().create_timer(1.0).timeout
			_coop.call("dev_hit_enemy_part", pid, 0, 50)
			await get_tree().create_timer(1.0).timeout
			print("[etn_coop] dev-part-late host net=%d part0=%d root=%d" % [pid, int(_coop.call("dev_enemy_part_hp", pid, 0)), int(_coop.call("dev_enemy_hp", pid))])
			await get_tree().create_timer(28.0).timeout
			print("[etn_coop] dev-part-late host alive part0=%d" % int(_coop.call("dev_enemy_part_hp", pid, 0)))
		else:
			await get_tree().create_timer(3.0).timeout
			var pid: int = int(_coop.call("dev_first_enemy_net_id"))
			await get_tree().create_timer(2.0).timeout
			print("[etn_coop] dev-part-late client net=%d part0=%d stats=%s" % [pid, int(_coop.call("dev_enemy_part_hp", pid, 0)), str(_coop.call("dev_part_stats"))])
	if devrejoin:
		var waited_rj: float = 0.0
		while not _coop.battle_active and waited_rj < 15.0:
			await get_tree().create_timer(0.2).timeout
			waited_rj += 0.2
		if mode == "host":
			await get_tree().create_timer(1.5).timeout
			var pid: int = int(_coop.call("dev_spawn_part_enemy"))
			await get_tree().create_timer(1.0).timeout
			_coop.call("dev_hit_enemy_part", pid, 0, 50)
			await get_tree().create_timer(2.0).timeout
			print("[etn_coop] dev-rejoin host net=%d part0=%d" % [pid, int(_coop.call("dev_enemy_part_hp", pid, 0))])
			await get_tree().create_timer(8.0).timeout
			for i in 3:
				_coop.call("dev_resend_existing")
				await get_tree().create_timer(2.0).timeout
			await get_tree().create_timer(4.0).timeout
			print("[etn_coop] dev-rejoin host final part0=%d" % int(_coop.call("dev_enemy_part_hp", pid, 0)))
		else:
			await get_tree().create_timer(8.0).timeout
			var pid: int = int(_coop.call("dev_first_enemy_net_id"))
			print("[etn_coop] dev-rejoin client initial net=%d part0=%d" % [pid, int(_coop.call("dev_enemy_part_hp", pid, 0))])
			_coop.call("dev_evict_enemy", pid)
			await get_tree().create_timer(1.0).timeout
			print("[etn_coop] dev-rejoin client evicted part0=%d" % int(_coop.call("dev_enemy_part_hp", pid, 0)))
			await get_tree().create_timer(12.0).timeout
			print("[etn_coop] dev-rejoin client restored part0=%d stats=%s" % [int(_coop.call("dev_enemy_part_hp", pid, 0)), str(_coop.call("dev_part_stats"))])
	if devscale:
		var waited_sc: float = 0.0
		while not _coop.battle_active and waited_sc < 15.0:
			await get_tree().create_timer(0.2).timeout
			waited_sc += 0.2
		await get_tree().create_timer(4.0).timeout
		if mode == "host":
			for k in 3:
				_coop.call("dev_spawn_real_enemy")
				await get_tree().create_timer(1.0).timeout
		for i in 6:
			print("[etn_coop] dev-scale id=%d\n%s" % [_coop.multiplayer.get_unique_id(), str(_coop.call("dev_turret_scale"))])
			await get_tree().create_timer(2.0).timeout
	if devfollows:
		var waited_fw: float = 0.0
		while not _coop.battle_active and waited_fw < 15.0:
			await get_tree().create_timer(0.2).timeout
			waited_fw += 0.2
		await get_tree().create_timer(1.5).timeout
		for item_id in ["black_ninpero", "kikyou_doll", "renge_doll", "yukari_doll", "voodoo_doll", "tnt"]:
			_coop.call("dev_grant_item", item_id)
			await get_tree().create_timer(0.6).timeout
		await get_tree().create_timer(1.5).timeout
		print("[etn_coop] dev-follows id=%d\n%s" % [_coop.multiplayer.get_unique_id(), str(_coop.call("dev_follow_marks"))])
	if devname:
		var waited_nm: float = 0.0
		while not _coop.battle_active and waited_nm < 15.0:
			await get_tree().create_timer(0.2).timeout
			waited_nm += 0.2
		await get_tree().create_timer(2.0).timeout
		print("[etn_coop] dev-name id=%d %s" % [_coop.multiplayer.get_unique_id(), str(_coop.call("dev_name_state"))])
		var lp = _coop.call("get_local_player")
		if lp != null:
			var spr = lp.get("sprite_2d")
			var tag = lp.get_node_or_null("CoopNameTag")
			if spr != null and tag != null:
				var base_y: float = spr.position.y
				var base_tag_y: float = tag.position.y
				spr.position.y = base_y - 40.0
				tag.call("_process", 0.0)
				print("[etn_coop] dev-name-jump id=%d tag %.1f -> %.1f (expect -40)" % [_coop.multiplayer.get_unique_id(), base_tag_y, tag.position.y])
				spr.position.y = base_y
		_coop.call("set_local_display_name", "测试玩家ABCDEFGHIJKLM")
		await get_tree().create_timer(1.5).timeout
		print("[etn_coop] dev-name-after-too-long id=%d %s" % [_coop.multiplayer.get_unique_id(), str(_coop.call("dev_name_state"))])
		_coop.call("set_local_display_name", "Nyangeon")
		await get_tree().create_timer(1.5).timeout
		print("[etn_coop] dev-name-after-save id=%d %s" % [_coop.multiplayer.get_unique_id(), str(_coop.call("dev_name_state"))])
	if devhp:
		var waited_hp: float = 0.0
		while not _coop.battle_active and waited_hp < 15.0:
			await get_tree().create_timer(0.2).timeout
			waited_hp += 0.2
		await get_tree().create_timer(2.0).timeout
		print("[etn_coop] dev-hp id=%d %s" % [_coop.multiplayer.get_unique_id(), str(_coop.call("dev_health_state"))])
		var lp_hp = _coop.call("get_local_player")
		if lp_hp != null and lp_hp.get("stats") != null:
			var st = lp_hp.stats
			st.hp = maxi(1, int(st.hp) - 20)
			st.t_hp = int(int(st.max_t_hp) / 2)
		await get_tree().create_timer(1.5).timeout
		print("[etn_coop] dev-hp-after id=%d %s" % [_coop.multiplayer.get_unique_id(), str(_coop.call("dev_health_state"))])
	if devcharevent:
		var waited_ce: float = 0.0
		while not _coop.battle_active and waited_ce < 15.0:
			await get_tree().create_timer(0.2).timeout
			waited_ce += 0.2
		await get_tree().create_timer(2.5).timeout
		_coop.call("dev_character_event_probe")
	if devmotion:
		var waited_mo: float = 0.0
		while not _coop.battle_active and waited_mo < 15.0:
			await get_tree().create_timer(0.2).timeout
			waited_mo += 0.2
		await get_tree().create_timer(2.0).timeout
		await _coop.call("dev_motion_probe")
	if devconvert:
		var waited_cv: float = 0.0
		while not _coop.battle_active and waited_cv < 15.0:
			await get_tree().create_timer(0.2).timeout
			waited_cv += 0.2
		await get_tree().create_timer(4.0).timeout
		if mode == "join":
			_coop.call("dev_convert_enemy", -1, 1000)
			await get_tree().create_timer(1.0).timeout
		_coop.call("dev_enemy_converted_state", -1)
		await get_tree().create_timer(3.0).timeout
		_coop.call("dev_enemy_converted_state", -1)
	if devhud:
		if _hud != null and is_instance_valid(_hud):
			_hud.call("set_shown", true)
		await get_tree().create_timer(1.5).timeout
		print("[etn_coop] dev-hud text:\n%s" % str(_coop.call("get_network_debug_text")))
	if devchat:
		var waited_ch: float = 0.0
		while not _coop.battle_active and waited_ch < 15.0:
			await get_tree().create_timer(0.2).timeout
			waited_ch += 0.2
		await get_tree().create_timer(2.0).timeout
		var my_id: int = _coop.multiplayer.get_unique_id()
		_coop.call("send_chat", "hello-from-%d" % my_id)
		await get_tree().create_timer(2.0).timeout
		print("[etn_coop] dev-chat id=%d log=%d %s" % [my_id, int(_coop.call("get_chat_log").size()), str(_coop.call("get_chat_log"))])
	if devflow:
		var waited_flow: float = 0.0
		while not str(_coop.get("current_scene_path")).contains("test_room") and waited_flow < 20.0:
			await get_tree().create_timer(0.2).timeout
			waited_flow += 0.2
		await get_tree().create_timer(2.0).timeout
		print("[etn_coop] dev-flow in lobby id=%d" % _coop.multiplayer.get_unique_id())
		var catalog: Array = _coop.call("get_level_catalog")
		print("[etn_coop] dev-flow catalog=%s" % str(catalog.map(func(e): return e.get("id"))))
		if devready and mode == "join":
			await get_tree().create_timer(1.0).timeout
			_coop.call("toggle_local_ready")
			print("[etn_coop] dev-ready client ready=%s" % str(_coop.get("lobby_ready_by_peer")))
		if mode == "host":
			# 等客机进入准备房再开始选人，避免竞态
			await get_tree().create_timer(4.0).timeout
			if devready:
				print("[etn_coop] dev-ready host before-all=%s" % str(_coop.call("are_all_players_ready")))
				var wr0: float = 0.0
				while not bool(_coop.call("are_all_players_ready")) and wr0 < 10.0:
					await get_tree().create_timer(0.2).timeout
					wr0 += 0.2
				print("[etn_coop] dev-ready host after-all=%s wait=%.1f" % [str(_coop.call("are_all_players_ready")), wr0])
			_coop.call("request_begin_select")
		var wait2: float = 0.0
		while int(_coop.get("_flow_phase")) != 2 and wait2 < 10.0:
			await get_tree().create_timer(0.2).timeout
			wait2 += 0.2
		print("[etn_coop] dev-flow pre-confirm id=%d paused=%s phase=%d" % [_coop.multiplayer.get_unique_id(), str(get_tree().paused), int(_coop.get("_flow_phase"))])
		if devabort:
			# 验证房主 Esc 取消整轮选人：应回准备房并解除暂停
			if mode == "host":
				_coop.call("abort_select_to_lobby")
			await get_tree().create_timer(2.0).timeout
			print("[etn_coop] dev-flow aborted id=%d phase=%d paused=%s scene=%s" % [_coop.multiplayer.get_unique_id(), int(_coop.get("_flow_phase")), str(get_tree().paused), str(_coop.get("current_scene_path"))])
		else:
			# 走真实 UI 回调：选人覆盖层监听 player_card_id → CoopFlow 确认 → 已就绪遮罩
			GameEvents.emit_player_card_id("res://scenes/player/momoi/momoi.tscn")
			var wait3: float = 0.0
			while int(_coop.get("_flow_phase")) != 3 and wait3 < 10.0:
				await get_tree().create_timer(0.2).timeout
				wait3 += 0.2
			print("[etn_coop] dev-flow select-ready id=%d phase=%d" % [_coop.multiplayer.get_unique_id(), int(_coop.get("_flow_phase"))])
			await get_tree().create_timer(1.0).timeout
			if mode == "host":
				# 走与难度按钮相同的路径：GameEvents.change_scene → CoopNet 的 ALL_READY gate 分支
				GameEvents.change_scene("res://scenes/main/main.tscn", str(_coop.get("local_player_scene_path")))
			await get_tree().create_timer(3.0).timeout
			print("[etn_coop] dev-flow after id=%d phase=%d scene=%s" % [_coop.multiplayer.get_unique_id(), int(_coop.get("_flow_phase")), str(_coop.get("current_scene_path"))])
	var tail: float = 8.0 if mode == "host" else 4.0
	await get_tree().create_timer(tail).timeout
	var api = _coop.multiplayer
	print("[etn_coop] dev status: mode=%s id=%d peers=%s battle=%s remotes=%d enemies=%d enemy1=%d visuals=%d effects=%d coins=%d summons=%d rdown=%d downed=%s prompt=%s bev=%d ext=%d snap=%d hit=%d/%d team=%s" % [
		mode, api.get_unique_id(), str(api.get_peers()), str(_coop.battle_active),
		_coop.player_by_peer_id.size(), _coop.enemy_by_net_id.size(),
		int(_coop.call("dev_enemy_hp", 1)), int(_coop.call("dev_visual_count")),
		int(_coop.call("dev_effect_count")), int(_coop.call("dev_player_coins")),
		int(_coop.call("dev_summoned_count")), int(_coop.call("dev_remote_downed_count")),
		str(_coop.call("dev_local_downed")), str(_coop.call("dev_rescue_prompt_shown")),
		int(_coop.call("dev_boss_events_received")), int(_coop.net_extrap_events), int(_coop.net_hard_snaps),
		int(_coop.net_hits_accepted), int(_coop.net_hits_rejected), str(_coop.call("dev_team_stats"))])
	await get_tree().create_timer(3.0).timeout
	# --coop-devquit：房主离开自测，不主动关连接，交给 CoopNet 检测并回主菜单后优雅退出
	if "--coop-devquit" in OS.get_cmdline_user_args():
		return
	if _coop != null:
		_coop.call("close_connection", true)
	await get_tree().process_frame
	get_tree().quit()
