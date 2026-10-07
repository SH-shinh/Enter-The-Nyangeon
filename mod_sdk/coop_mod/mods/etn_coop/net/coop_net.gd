extends Node

## CoopNet：联机骨架核心（mod 内，非 autoload）。
## 通过 ExtensionHooks 挂接本体流程，不改本体。当前为骨架：
##   - LAN 主机/加入（ENet）、中继（WebSocket）传输已接；玩法同步（玩家/敌人/子弹/金币）为后续。
##   - 所有 gate 默认放行（返回 false / true），保证单机与未联机时零影响。
## 跨脚本访问：const Cooper = preload(...); Cooper.instance。

const TransportScript := preload("res://mods/etn_coop/net/coop_network_transport.gd")
const PlayerProxyScript := preload("res://mods/etn_coop/net/coop_player_proxy.gd")
const EnemyProxyScript := preload("res://mods/etn_coop/net/coop_enemy_proxy.gd")
const VisualSyncScript := preload("res://mods/etn_coop/net/coop_visual_sync.gd")
const SummonedProxyScript := preload("res://mods/etn_coop/net/coop_summoned_proxy.gd")
const SettingsScript := preload("res://mods/etn_coop/net/coop_settings.gd")
const NameTagScript := preload("res://mods/etn_coop/net/coop_name_tag.gd")
const ItemVisuals := preload("res://mods/etn_coop/net/coop_item_visuals.gd")
const MotionDownScript := preload("res://mods/etn_coop/ui/motion_down_screen.gd")
const SnapshotBuffer := preload("res://mods/etn_coop/net/coop_snapshot_buffer.gd")
const LanDiscoveryScript := preload("res://mods/etn_coop/net/coop_lan_discovery.gd")
const RoomFont := preload("res://fonts/BoutiqueBitmap7x7_1.7.ttf")
const PAUSE_ROOM_OFFSET_Y: float = 40.0

const DEFAULT_PLAYER_SCENE: String = "res://scenes/player/momoi/momoi.tscn"
const LOBBY_SCENE: String = "res://scenes/main/test_room.tscn"
const DEFAULT_BATTLE_SCENE: String = "res://scenes/main/main.tscn"
const MENU_SCENE: String = "res://scenes/main/menu_screen.tscn"
# 协议/版本握手：不一致直接拒绝
const PROTOCOL_VERSION: int = 1
const MOD_VERSION: String = "0.1.0"
const HELLO_TIMEOUT_MSEC: int = 5000

# 房主存活心跳：房主每 HOST_HEARTBEAT_INTERVAL 广播一次；客户端超过 HOST_TIMEOUT_MSEC 未收到
# 即判定房主离开（ENet 在本机/断网时不一定及时触发 server_disconnected）。
const HOST_HEARTBEAT_INTERVAL: float = 1.0
const HOST_TIMEOUT_MSEC: int = 8000

# 准备房流程阶段
enum FlowPhase { IDLE, LOBBY, SELECT, ALL_READY, BATTLE }

# auto_enter_lobby=false 时（无头开发自测）开房不自动进准备房，保持旧行为
var auto_enter_lobby: bool = true
var _flow_phase: int = FlowPhase.IDLE
var _select_flow_active: bool = false
# 房主离开（LAN/Relay）：正在执行「提示 + 过场回主菜单」，用于去重与防止重复触发
var _returning_to_menu_due_to_close: bool = false
# 房主存活心跳（客户端侧）
var _last_heartbeat_send_msec: int = 0
var _last_host_packet_msec: int = 0
var select_ready_by_peer: Dictionary = {}   # peer_id -> true（选人阶段“已就绪”）
var lobby_ready_by_peer: Dictionary = {}    # peer_id -> true（大厅“已准备”，开始球）
var _level_catalog: Array = []              # [{id,name,level,scene_path}]
var _level_catalog_built: bool = false

# 特效广播时按白名单收集的可视/可序列化属性（缺失则跳过）
const EFFECT_PROP_NAMES: Array[String] = [
	"explosion_range", "base_explosion_range", "damage_mult", "range_mult",
	"scale_mult", "is_crit", "color", "modulate", "bullet_scale", "source_faction",
]

# 子弹广播时按白名单收集的弹道属性（对齐联机版 player_bullet/bullet_launcher 传入的属性）
const BULLET_PROP_NAMES: Array[String] = [
	"penetrate", "collision_num", "can_r", "homing", "slow_down", "slow_time",
	"target_position", "decay_time", "decay_speed", "bullet_damage",
	"shoot_bullet_num", "shrapnel_random_speed", "explosion_range",
]

signal connection_status_changed(message: String)
signal boss_pattern_event_received(net_id: int, event_data: Dictionary)
signal character_select_requested
signal relay_room_created(room_code: String)
# 准备房流程（测试房 = 准备房 → 开始球 → 选人 → 就绪 → 房主难度 → 进关卡）
signal select_begin
signal select_all_ready
signal select_cancelled
signal select_aborted
signal select_ready_changed(peer_id: int, ready: bool)
# 聊天室：收到/本地回显一条消息（内容已解析为显示名）
signal chat_received(peer_id: int, name: String, text: String)

static var instance: Node = null

const DEFAULT_PORT: int = 24591
const MAX_PLAYERS: int = 4

var is_lan_game: bool = false
var transport = null  # CoopNetworkTransport（未类型化，避免 class_name 依赖）
var is_relay: bool = false
var relay_room_code: String = ""
var relay_server_url: String = "127.0.0.1:7716"
var _discovery = null  # CoopLanDiscovery
var dev_fake_game_version: String = ""  # 仅自测：模拟版本不一致

# ---------------- 玩家同步状态 ----------------
const STATE_SEND_INTERVAL: float = 0.05
const SPAWN_RADIUS: float = 28.0
const SPAWN_OFFSETS: Array[Vector2] = [Vector2(0, 0), Vector2(28, 0), Vector2(-28, 0), Vector2(0, 28)]

var battle_active: bool = false
var local_player_scene_path: String = ""
var current_scene_path: String = ""
var player_scene_by_peer: Dictionary = {}   # peer_id -> scene_path
var player_by_peer_id: Dictionary = {}      # peer_id -> Node
var player_proxy_by_peer_id: Dictionary = {}# peer_id -> Node
var player_name_by_peer: Dictionary = {}    # peer_id -> 显示名（空=未设置，回退 PlayerN）
var _state_timer: float = 0.0
var selected_player_scene_by_peer: Dictionary = {}
var scene_ready_peers: Dictionary = {}
var _handshaked_peers: Dictionary = {}   # peer_id -> true（版本握手通过）
var _pending_hello: Dictionary = {}      # peer_id -> 连接时刻（未握手超时踢除）
var _applying_change: bool = false
var _force_release: bool = false
var _pending_scene_path: String = ""
var first_round_emitted: bool = false
var _placement_token: int = 0
var _respawn_token: int = 0

# ---------------- 敌人同步状态 ----------------
const ENEMY_SNAPSHOT_INTERVAL: float = 0.066
const ENEMY_SNAPSHOT_HEARTBEAT_MSEC: int = 600
const ENEMY_SNAPSHOT_POS_EPS2: float = 0.25
const ENEMY_SNAPSHOT_VEL_EPS2: float = 0.25
# 优先级分频：近敌每 tick 发，中距每 2 tick，远距每 3 tick
const ENEMY_SNAP_NEAR_DIST: float = 420.0
const ENEMY_SNAP_MID_DIST: float = 900.0
# 单包实体上限：ENet 对 unreliable 包不重组，超过 MTU 会整包丢弃 → 切包发送
const ENEMY_SNAPSHOT_ENTITY_LIMIT: int = 32
const DEATH_GPU := preload("res://script/death_gpu.tscn")
const TEST_ROOM_NET_BASE: int = 100000

var enemy_by_net_id: Dictionary = {}          # net_id -> Node
var enemy_scene_by_net_id: Dictionary = {}    # net_id -> scene_path
var enemy_proxy_by_net_id: Dictionary = {}    # net_id -> Node
var next_enemy_net_id: int = 1
var _snapshot_timer: float = 0.0
var _enemy_snap_cache: Dictionary = {}        # net_id -> {p,v,h,t}
var _enemy_snap_tick: int = 0
var _enemy_snap_next_tick: Dictionary = {}    # net_id -> 下次可发送 tick（优先级分频）
var enemy_snapshot_batch_limit: int = ENEMY_SNAPSHOT_ENTITY_LIMIT
var last_attacker_by_net_id: Dictionary = {}  # net_id -> owner_peer（击杀归属用）
# 实时战绩（host 权威，周期广播）
const TEAM_STATS_INTERVAL: float = 1.0
var team_stats: Dictionary = {}   # pid -> {kills, damage, coins}
var _team_stats_timer: float = 0.0
# 聊天室：本次联机房间的全部消息（按加入顺序），回菜单/重开即清空
const CHAT_LOG_MAX: int = 200
const CHAT_TEXT_MAX: int = 120
var chat_log: Array = []          # 元素 {peer_id:int, name:String, text:String}
# 命中轻量校验：host 记录敌人位置历史（回滚合理性），保持客户端权威、仅拦明显异常
const HIT_VALIDATE_MAX_DIST: float = 2400.0
const HIT_VALIDATE_TOL: float = 200.0
const HIT_HISTORY_MAX: int = 16
var _enemy_pos_history: Dictionary = {}       # net_id -> Array[{t,p}]
var net_hits_accepted: int = 0
var net_hits_rejected: int = 0

# ---------------- 子弹/视觉同步状态 ----------------
const BULLET_BATCH_LIMIT: int = 128
var _visual = VisualSyncScript.new()
var _pending_visual: Array = []
var _pending_visual_reliable: Array = []   # 一次性关键投射物（打 coop_reliable_visual meta 的）
var _pending_effects: Array = []
var _next_visual_id: int = 1

# ---------------- 远程命中反馈（其它玩家来源）频率门 ----------------
const REMOTE_FLASH_BASE_MS: int = 60
const REMOTE_EFFECT_BASE_MS: int = 33
const REMOTE_SPARK_SCENE: String = "res://scenes/bullet/bullet_smoke.tscn"
var settings = SettingsScript.new()
var _remote_fx_last_ms: Dictionary = {}
var _remote_flash_last_ms: Dictionary = {}
var _remote_text_counter: int = 0
# 远端命中音效限流（多玩家叠加时避免音效过多）：每 key 间隔 + 全局最小间隔，复用 remote_effect_freq 档位
const REMOTE_HITSFX_KEY_BASE_MS: int = 80
const REMOTE_HITSFX_GLOBAL_MIN_MS: int = 33
var _remote_sfx_last_ms: Dictionary = {}
var _remote_sfx_last_global_ms: int = -1000000000
# 回放命中反馈期间置位：抑制连在 damage_taken 上的 _on_server_enemy_damage_taken 重复广播
var _replaying_feedback: bool = false
# 应用"远端镜像 buff"期间置位：让 enemy_buff_apply_gate 放行（避免再次转发）
var _applying_remote_buff: bool = false

# ---------------- 网络诊断（HUD 用，对齐联机版） ----------------
const NET_DIAG_INTERVAL: float = 0.5
const NET_DIAG_TIMEOUT_MSEC: int = 2000
const NET_DIAG_SAMPLE_LIMIT: int = 40
var net_diag_enabled: bool = false
var _diag_elapsed: float = 0.0
var _diag_seq: int = 0
var _diag_pending: Dictionary = {}
var _latency_samples: Array = []
var _delivery_samples: Array = []
# 网络补偿调试计数（供 F9 HUD）
var net_extrap_events: int = 0
var net_hard_snaps: int = 0
# 压测：可配置网络模拟（延迟+抖动+丢包，作用于收到的敌人快照）
var sim_latency_ms: float = 0.0
var sim_jitter_ms: float = 0.0
var sim_loss_pct: float = 0.0
var sim_report_enabled: bool = false
var _sim_report_timer: float = 0.0
var _sim_snapshot_queue: Array = []
const SIM_REPORT_INTERVAL: float = 2.0
# 压测指标
var net_remote_frames: int = 0     # 远端实体渲染帧数（客户端）
var net_extrap_frames: int = 0     # 其中处于外推的帧数
var net_snapshot_sends: int = 0    # host 发出的敌人快照包数
var net_snapshot_entities: int = 0 # host 累计发出的敌人条目数
# 缓存 RTT/抖动（供远端 proxy 计算自适应插值延迟，避免每帧方法调用/字典分配）
var net_rtt_ms: float = 0.0
var net_jitter_ms: float = 0.0
var net_bullet_sent: int = 0
var net_bullet_recv: int = 0
var net_effect_sent: int = 0
var net_effect_recv: int = 0
var _rate_bullet_sent: float = 0.0
var _rate_bullet_recv: float = 0.0
var _rate_effect_sent: float = 0.0
var _rate_effect_recv: float = 0.0
var _rate_last_bullet_sent: int = 0
var _rate_last_bullet_recv: int = 0
var _rate_last_effect_sent: int = 0
var _rate_last_effect_recv: int = 0
var _rate_window_msec: int = 0

# ---------------- 金币同步状态 ----------------
var coin_by_net_id: Dictionary = {}
var next_coin_net_id: int = 1

# ---------------- 召唤物同步状态 ----------------
var summoned_by_net_id: Dictionary = {}
var summoned_proxy_by_net_id: Dictionary = {}
var summoned_scene_by_net_id: Dictionary = {}
var summoned_owner_by_net_id: Dictionary = {}
var pending_local_summons: Array = []       # [{"node":Node,"scene":String}] 等 host 分配 net_id 后认领
var next_summoned_net_id: int = 1

# 非 Summoned 但含 AI 的"持久身体"（道具召唤）：走召唤同步通道做仅视觉镜像 + 变换同步
const PERSISTENT_BODY_SCENES: Array[String] = [
	"res://scenes/update_item/shiroko_drone_body.tscn",
	"res://scenes/update_item/robotic_vacuum_cleaner_body.tscn",
]

# ---------------- 倒地/救援状态 ----------------
const RESCUE_RADIUS: float = 96.0
const RESCUE_TIME: float = 2.5
const REVIVE_HEALTH_MULT: float = 0.5
var down_peer_ids: Dictionary = {}
var _rescue_target: Node = null
var _rescue_hold: float = 0.0
var _rescue_prompt: Node = null
var _rescue_prompt_scene: PackedScene = null
var _rescue_prompt_shown: bool = false
# 暂停页房间号（关卡内显示）
var _pause_room_panel: PanelContainer = null
var _pause_room_label: Label = null

# ---------------- 团队流程状态 ----------------
var round_upgrade_ready_peers: Dictionary = {}
var team_game_over_forced: bool = false
var boss_events_received: int = 0


func _ready() -> void:
	# 网络管理器常驻：选人阶段会全局暂停世界，本节点需在暂停下继续处理 RPC/握手
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings.load_settings()
	_discovery = LanDiscoveryScript.new()
	_discovery.name = "CoopLanDiscovery"
	add_child(_discovery)
	GameEvents.enemy_damage_taken.connect(_dev_on_enemy_damage_taken)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# 退出/关窗/被释放时确保关闭 ENet/中继，尽量释放端口
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		if transport != null or is_lan_game or is_relay:
			close_connection(true)


func _on_peer_connected(id: int) -> void:
	print("[etn_coop] peer connected: %d (total=%d)" % [id, multiplayer.get_peers().size()])
	if not multiplayer.is_server():
		return
	# 等版本/协议握手通过后再接入（见 _client_hello / _accept_peer）
	_pending_hello[id] = Time.get_ticks_msec()


func _on_peer_disconnected(id: int) -> void:
	print("[etn_coop] peer disconnected: %d" % id)
	# 客户端视角：peer 1（房主）离开 = 房间关闭 → 提示并过场回主菜单
	if id == 1 and not multiplayer.is_server() and _should_return_client_to_menu():
		_schedule_host_left_return()
	var p = player_by_peer_id.get(id)
	if p != null and is_instance_valid(p):
		p.queue_free()
	player_by_peer_id.erase(id)
	player_proxy_by_peer_id.erase(id)
	player_scene_by_peer.erase(id)
	scene_ready_peers.erase(id)
	lobby_ready_by_peer.erase(id)
	_handshaked_peers.erase(id)
	_pending_hello.erase(id)


func _on_connected_to_server() -> void:
	print("[etn_coop] connected to server")
	_last_host_packet_msec = Time.get_ticks_msec()
	# 版本/协议握手：客户端主动上报，host 校验
	var gv: String = Game.version_number if dev_fake_game_version == "" else dev_fake_game_version
	rpc_id(1, "_client_hello", PROTOCOL_VERSION, MOD_VERSION, gv)


# host：校验客机版本/协议；不一致 → 拒绝并尝试踢除
@rpc("any_peer", "call_remote", "reliable")
func _client_hello(proto: int, _mod_ver: String, game_ver: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if proto != PROTOCOL_VERSION or game_ver != Game.version_number:
		var reason: String = "protocol" if proto != PROTOCOL_VERSION else "game_version"
		print("[etn_coop] handshake reject peer=%d reason=%s (proto=%d game=%s)" % [sender, reason, proto, game_ver])
		rpc_id(sender, "_hello_reject", reason)
		_kick_peer_deferred(sender)
		return
	_pending_hello.erase(sender)
	_handshaked_peers[sender] = true
	_accept_peer(sender)


@rpc("authority", "call_remote", "reliable")
func _hello_reject(reason: String) -> void:
	if multiplayer.is_server():
		return
	print("[etn_coop] handshake rejected by host: %s" % reason)
	connection_status_changed.emit("Version mismatch")
	_show_session_closed_notice("coop_version_mismatch")
	close_connection(true)


# 握手通过后：按当前阶段把新客机送进准备房 / 补发 roster 与已存在实体
func _accept_peer(id: int) -> void:
	selected_player_scene_by_peer[id] = DEFAULT_PLAYER_SCENE
	player_scene_by_peer[id] = DEFAULT_PLAYER_SCENE
	rpc_id(id, "_hello_accept")
	if _flow_phase == FlowPhase.LOBBY and current_scene_path.contains("test_room"):
		rpc_id(id, "_remote_change_scene", LOBBY_SCENE, player_scene_by_peer, {})
		return
	if battle_active:
		rpc_id(id, "_client_sync_roster", player_scene_by_peer)
		_send_existing_enemies_to_peer(id)
		_send_existing_summons_to_peer(id)


@rpc("authority", "call_remote", "reliable")
func _hello_accept() -> void:
	if multiplayer.is_server():
		return
	print("[etn_coop] handshake accepted by host")


# 延迟踢除：给可靠 reject 包留出送达时间（立即 disconnect 会丢包）
func _kick_peer_deferred(id: int) -> void:
	await get_tree().create_timer(0.5).timeout
	if multiplayer.multiplayer_peer == null:
		return
	var peer = multiplayer.multiplayer_peer
	if peer != null and peer.has_method("disconnect_peer"):
		peer.call("disconnect_peer", id)


# 房主存活心跳：房主定期广播，客户端超时判定房主离开（不依赖 ENet 超时）。
# 一律用墙钟计时，避免场景切换 / Engine.time_scale 造成发送间隔漂移。
func _network_heartbeat(_delta: float) -> void:
	if not is_lan_game:
		return
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		var now: int = Time.get_ticks_msec()
		if now - _last_heartbeat_send_msec >= int(HOST_HEARTBEAT_INTERVAL * 1000.0):
			_last_heartbeat_send_msec = now
			rpc("_host_heartbeat")
		return
	if _last_host_packet_msec <= 0:
		_last_host_packet_msec = Time.get_ticks_msec()
		return
	if Time.get_ticks_msec() - _last_host_packet_msec > HOST_TIMEOUT_MSEC:
		_last_host_packet_msec = Time.get_ticks_msec()
		_schedule_host_left_return()


@rpc("authority", "call_remote", "reliable")
func _host_heartbeat() -> void:
	if multiplayer.is_server():
		return
	_last_host_packet_msec = Time.get_ticks_msec()


# ---------------- LAN 房间发现 ----------------

func browse_lan_start() -> void:
	if _discovery != null:
		_discovery.call("browse_start")


func browse_lan_stop() -> void:
	if _discovery != null:
		_discovery.call("browse_stop")


func get_lan_rooms() -> Array:
	if _discovery != null:
		return _discovery.call("get_rooms")
	return []


func dev_lan_rooms() -> int:
	return get_lan_rooms().size()


# 仅 LAN 主机播报；其它情形停止
func _update_lan_advertise() -> void:
	if _discovery == null:
		return
	if is_lan_game and not is_relay and multiplayer.is_server() and multiplayer.multiplayer_peer != null:
		_discovery.call("advertise_ensure", {
			"name": _local_display_name(),
			"port": DEFAULT_PORT,
			"players": multiplayer.get_peers().size() + 1,
			"max": MAX_PLAYERS,
			"mode": "battle" if battle_active else "lobby",
			"game_version": Game.version_number,
		})
	elif bool(_discovery.call("is_advertising")):
		_discovery.call("advertise_stop")


# host：未在 HELLO_TIMEOUT_MSEC 内完成握手的连接踢除
func _update_handshake_timeouts() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not multiplayer.is_server() or _pending_hello.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	for id in _pending_hello.keys():
		if now - int(_pending_hello[id]) > HELLO_TIMEOUT_MSEC:
			_pending_hello.erase(id)
			if not bool(_handshaked_peers.get(id, false)):
				var peer = multiplayer.multiplayer_peer
				if peer != null and peer.has_method("disconnect_peer"):
					peer.call("disconnect_peer", id)


# 实时战绩（host 权威，周期广播）
func _ensure_team_stat(pid: int) -> Dictionary:
	var d = team_stats.get(pid)
	if d == null:
		d = {"kills": 0, "damage": 0, "coins": 0}
		team_stats[pid] = d
	return d


func _add_team_damage(pid: int, amount: int) -> void:
	if not multiplayer.is_server() or amount <= 0:
		return
	_ensure_team_stat(pid)["damage"] += amount


func _add_team_kill(pid: int) -> void:
	if not multiplayer.is_server():
		return
	_ensure_team_stat(pid)["kills"] += 1


func _broadcast_team_stats() -> void:
	if not multiplayer.is_server():
		return
	var coin: int = 0
	var p := get_local_player()
	if p != null and p.get("stats") != null:
		coin = int(p.stats.coin)
	_ensure_team_stat(multiplayer.get_unique_id())
	for pid in team_stats.keys():
		team_stats[pid]["coins"] = coin
	rpc("_remote_team_stats", team_stats.duplicate(true))


@rpc("authority", "call_remote", "reliable")
func _remote_team_stats(d: Dictionary) -> void:
	if multiplayer.is_server():
		return
	team_stats = d


func dev_team_stats() -> String:
	var parts: Array = []
	for pid in team_stats.keys():
		var d = team_stats[pid]
		parts.append("%d:k/d/c=%d/%d/%d" % [int(pid), int(d.get("kills", 0)), int(d.get("damage", 0)), int(d.get("coins", 0))])
	return " | ".join(parts) if parts.size() > 0 else "(none)"


func _on_connection_failed() -> void:
	push_warning("[etn_coop] connection failed")
	connection_status_changed.emit("Connection failed")
	close_connection.call_deferred(true)


func _on_server_disconnected() -> void:
	push_warning("[etn_coop] server disconnected")
	connection_status_changed.emit("Server disconnected")
	if _should_return_client_to_menu():
		_schedule_host_left_return()
	else:
		close_connection.call_deferred(true)


# 是否处于「客户端 + 联机会话中」：房主离开时应回主菜单
func _should_return_client_to_menu() -> bool:
	if _returning_to_menu_due_to_close:
		return false
	if multiplayer.is_server():
		return false
	return is_lan_game or is_relay


# 同步占位去重，再 deferred 执行。
# 严禁在 multiplayer 信号回调栈内改 multiplayer_peer（释放 ENet/中继）——会崩溃。
func _schedule_host_left_return() -> void:
	if _returning_to_menu_due_to_close:
		return
	_returning_to_menu_due_to_close = true
	call_deferred("_handle_host_left")


# 房主离开统一入口：解除暂停 → 提示 → 过场 → 回主菜单（LAN/Relay 通用）
func _handle_host_left() -> void:
	var tree := get_tree()
	if tree == null:
		return
	# 等一帧脱离 multiplayer 信号回调栈，避免在 poll 内释放传输崩溃
	await tree.process_frame
	if get_tree() == null:
		return
	print("[etn_coop] host session closed -> return to menu")
	# 解除选人/升级/暂停菜单造成的暂停与受控（否则转场后仍卡住）
	_set_select_pause(false)
	tree.paused = false
	# 立即清理传输与 run state，避免继续向已消失的房主发包
	close_connection(true)
	_show_session_closed_notice()
	# 让提示停留一会儿再转场（create_timer 默认 process_always，暂停下也会到期）
	await tree.create_timer(1.5).timeout
	await _play_remote_scene_transition_start()
	if get_tree() == null:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameEvents.change_scene(MENU_SCENE, "")
	await tree.tree_changed
	if get_tree() != null and get_tree().current_scene != null:
		print("[etn_coop] returned to menu: %s" % get_tree().current_scene.scene_file_path)
	# 无头自测：--coop-devquit 让客户端回菜单后优雅退出（刷新 stdout）
	if "--coop-devquit" in OS.get_cmdline_user_args():
		await tree.create_timer(0.5).timeout
		tree.quit()


# 在黄条位置弹底部 toast（复用本体 mobile_notice）；挂当前场景下，切场景随之释放
func _show_session_closed_notice(key: String = "coop_host_left") -> void:
	var tree := get_tree()
	if tree == null:
		return
	var host_parent: Node = tree.current_scene
	if host_parent == null or not is_instance_valid(host_parent):
		host_parent = tree.root
	if host_parent == null:
		return
	var layer := CanvasLayer.new()
	layer.name = "CoopSessionClosedNotice"
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host_parent.add_child(layer)
	var notice_scene := load("res://ui/mobile_notice.tscn") as PackedScene
	if notice_scene == null:
		return
	var notice: Node = notice_scene.instantiate()
	layer.add_child(notice)
	if notice.has_method("notice"):
		notice.call("notice", key)


# ---------------- 钩子接线 ----------------

func install_hooks() -> void:
	ExtensionHooks.change_scene_gate = Callable(self, "_gate_change_scene")
	ExtensionHooks.first_round_start_gate = Callable(self, "_gate_first_round")
	ExtensionHooks.enemy_damage_interceptor = Callable(self, "_intercept_enemy_damage")
	ExtensionHooks.coin_pickup_gate = Callable(self, "_gate_coin_pickup")
	ExtensionHooks.player_death_gate = Callable(self, "_gate_player_death")
	ExtensionHooks.game_over_gate = Callable(self, "_gate_game_over")
	ExtensionHooks.round_upgrade_end_gate = Callable(self, "_gate_round_upgrade_end")
	ExtensionHooks.round_end_emit_gate = Callable(self, "_gate_round_end_emit")
	ExtensionHooks.round_end_proceed_gate = Callable(self, "_gate_round_end_proceed")
	ExtensionHooks.projectile_self_hit_gate = Callable(self, "_gate_projectile_self_hit")
	ExtensionHooks.enemy_buff_apply_gate = Callable(self, "_gate_enemy_buff_apply")
	ExtensionHooks.round_enemy_spawn_gate = Callable(self, "_gate_round_enemy_spawn")
	ExtensionHooks.enemy_conversion_interceptor = Callable(self, "_gate_enemy_conversion")
	ExtensionHooks.enemy_proc_owner_suppress = Callable(self, "_gate_enemy_proc_owner_suppress")

	ExtensionHooks.on_projectile_spawned = Callable(self, "_on_projectile_spawned")
	ExtensionHooks.on_projectile_despawned = Callable(self, "_on_projectile_despawned")
	ExtensionHooks.on_enemy_spawned = Callable(self, "_on_enemy_spawned")
	ExtensionHooks.on_summoned_spawned = Callable(self, "_on_summoned_spawned")
	ExtensionHooks.on_summoned_despawned = Callable(self, "_on_summoned_despawned")
	ExtensionHooks.on_coin_spawned = Callable(self, "_on_coin_spawned")
	ExtensionHooks.on_player_downed = Callable(self, "_on_player_downed")
	ExtensionHooks.on_player_revived = Callable(self, "_on_player_revived")
	ExtensionHooks.on_player_melee = Callable(self, "_on_player_melee")
	ExtensionHooks.on_player_reload = Callable(self, "_on_player_reload")
	ExtensionHooks.on_pyroxenes_gain = Callable(self, "_on_pyroxenes_gain")
	ExtensionHooks.on_enemy_buff_removed = Callable(self, "_on_enemy_buff_removed")
	ExtensionHooks.on_enemy_buff_applied = Callable(self, "_on_enemy_buff_applied")
	ExtensionHooks.on_explosion_effect = Callable(self, "_on_explosion_effect")
	ExtensionHooks.on_hit_sfx = Callable(self, "_on_hit_sfx")
	ExtensionHooks.on_summoned_action = Callable(self, "_on_summoned_action")
	ExtensionHooks.on_visual_activated = Callable(self, "_on_visual_activated")
	ExtensionHooks.on_pickup_spawned = Callable(self, "_on_pickup_spawned")
	ExtensionHooks.on_character_event = Callable(self, "_on_character_event")
	ExtensionHooks.local_player_change_gate = Callable(self, "_gate_local_player_change")
	ExtensionHooks.pause_visibility = Callable(self, "_on_pause_visibility")
	ExtensionHooks.is_lan_session = Callable(self, "_is_lan_session")

	GameEvents.first_round_add.connect(_on_first_round_add)
	GameEvents.round_start.connect(_on_round_start)
	GameEvents.round_upgrade.connect(_on_round_upgrade)
	GameEvents.round_end.connect(_on_local_round_end)
	GameEvents.test_room_reset.connect(_on_local_test_room_reset)
	GameEvents.ability_upgrade_added.connect(_on_local_ability_upgrade_added)
	GameEvents.player_is_hurt.connect(_on_local_player_hurt)
	GameEvents.player_projectile_hit.connect(_on_any_projectile_hit)
	GameEvents.player_gun_shoot.connect(_on_local_gun_shoot)
	GameEvents.boss_round_start.connect(_on_boss_round_start)
	GameEvents.boss_round_end.connect(_on_boss_round_end)
	GameEvents.boss_event.connect(_on_local_boss_event)


# ---------------- 接管类（骨架：默认放行） ----------------

# 返回 true = 接管场景切换。LAN host 等全员选定后放行本体加载；client 上报后跟随。
func _gate_change_scene(path: String, player: String) -> bool:
	if _applying_change or _force_release:
		_force_release = false
		current_scene_path = path
		if player != "":
			local_player_scene_path = player
		return false
	current_scene_path = path
	if player != "":
		local_player_scene_path = player
	if not is_lan_game:
		_reset_run_state()
		return false
	if path == "":
		_reset_run_state()
		return false
	# 返回菜单/离开对局：player 为空（对齐联机版）——先广播再复位，随后释放连接/端口
	if player == "":
		if multiplayer.is_server():
			rpc("_remote_return_to_menu", path)
		_reset_run_state()
		_close_transport_soon()
		return false
	_pending_scene_path = path
	if multiplayer.is_server():
		if player != "":
			selected_player_scene_by_peer[multiplayer.get_unique_id()] = player
		# 新流程：全员就绪后房主在难度面板选关 → 统一开战
		if _flow_phase == FlowPhase.ALL_READY:
			print("[etn_coop] host starts battle path=%s" % path)
			_select_flow_active = false
			_flow_phase = FlowPhase.BATTLE
			select_ready_by_peer.clear()
			_set_select_pause(false)
			_broadcast_roster()
			return false
		if not _all_expected_selected():
			var expected: Array = [multiplayer.get_unique_id()]
			for p in multiplayer.get_peers():
				expected.append(int(p))
			connection_status_changed.emit("Waiting for all players to select (%d/%d)" % [selected_player_scene_by_peer.size(), expected.size()])
			print("[etn_coop] host waiting for all players: %s" % str(selected_player_scene_by_peer))
			return true
		_broadcast_roster()
		# 放行本体 change_scene（本体负责加载场景并生成本地玩家）
		return false
	# client：上报选择，等待 host 广播
	if player != "":
		rpc_id(1, "_server_player_selected", player)
	return true


func _all_expected_selected() -> bool:
	if not multiplayer.is_server():
		return false
	var expected: Array = [multiplayer.get_unique_id()]
	for p in multiplayer.get_peers():
		expected.append(int(p))
	for p in expected:
		if not selected_player_scene_by_peer.has(p):
			return false
		if str(selected_player_scene_by_peer[p]) == "":
			return false
	return true


# host：整理 roster 广播给 client，并重置本局同步状态
func _broadcast_roster() -> void:
	_reset_player_sync()
	first_round_emitted = false
	scene_ready_peers.clear()
	player_scene_by_peer = selected_player_scene_by_peer.duplicate()
	if local_player_scene_path != "":
		player_scene_by_peer[multiplayer.get_unique_id()] = local_player_scene_path
	rpc("_remote_change_scene", _pending_scene_path, player_scene_by_peer, _build_level_state())
	print("[etn_coop] host broadcast roster path=%s roster=%s" % [_pending_scene_path, str(player_scene_by_peer)])


# ---------------- level_state（关卡难度系数同步） ----------------

func _build_level_state() -> Dictionary:
	return {
		"level_id": str(PlayerData.level_id),
		"level_num": float(PlayerData.level_num),
		"level_hp": float(PlayerData.level_hp),
		"level_damage": float(PlayerData.level_damage),
		"level_score_mult": float(PlayerData.level_score_mult),
		"level_reward": float(PlayerData.level_reward),
		"game_mode": PlayerData.game_mode.duplicate(),
	}


func _apply_level_state(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	PlayerData.level_id = str(d.get("level_id", PlayerData.level_id))
	PlayerData.level_num = float(d.get("level_num", PlayerData.level_num))
	PlayerData.level_hp = float(d.get("level_hp", PlayerData.level_hp))
	PlayerData.level_damage = float(d.get("level_damage", PlayerData.level_damage))
	PlayerData.level_score_mult = float(d.get("level_score_mult", PlayerData.level_score_mult))
	PlayerData.level_reward = float(d.get("level_reward", PlayerData.level_reward))
	if d.has("game_mode"):
		var gm = d.get("game_mode")
		if gm is Array:
			PlayerData.game_mode = (gm as Array).duplicate()



# 仅 host/单机在本地启动回合；client 等待后续网络广播。
func _gate_first_round() -> bool:
	if not is_lan_game:
		return true
	return multiplayer.is_server()


# 自管理（玩家）子弹命中敌人：客机转发给 host 权威结算，同时在本地回放本子弹生命周期
# （穿透/命中烟/回池，action 由 HitBox.run_remote_hit 提供），返回 true 跳过本地 hit_received。
func _gate_projectile_self_hit(bullet: Node, hb) -> bool:
	if not is_lan_game or multiplayer.is_server():
		return false
	if bullet == null or not is_instance_valid(bullet) or hb == null or not is_instance_valid(hb):
		return false
	var ent: Node = _net_entity_of(hb)
	if ent == null:
		return false
	var data = bullet.get("damage_data")
	if data == null or not (data is DamageData):
		return false
	if ent.has_meta("coop_owner_net_id"):
		_handle_part_hit(ent, data)
		return true
	var enemy: Node = ent
	data.owner_peer = multiplayer.get_unique_id()
	var net_id: int = int(enemy.get_meta("net_id"))
	# 即时预测：闪白+飘字+镜像血条下调 + 预测死亡（不等 host 回传）
	var predicted: int = _get_predicted_enemy_damage(enemy, data.base_damage)
	_replay_hit_feedback(enemy, data, predicted, false)
	_predict_enemy_death(enemy, predicted, net_id)
	# 本地回放命中闭包（子弹生命周期 + player.damage_dealt；host 转发伤害无闭包，不会重复）
	for cb in data.on_damage_dealt:
		if cb is Callable:
			cb.call(enemy, data.base_damage)
	var victim_pos: Vector2 = (enemy as Node2D).global_position if enemy is Node2D else Vector2.ZERO
	rpc_id(1, "_server_enemy_hit", net_id, _damage_to_dict(data), victim_pos)
	return true


# 从节点向上找带 net_id 的实体（HurtBox → 敌人镜像）；部件镜像带 coop_owner_net_id（优先）
func _net_entity_of(node: Node) -> Node:
	var n: Node = node
	while n != null:
		if n.has_meta("coop_owner_net_id") or n.has_meta("net_id"):
			return n
		n = n.get_parent()
	return null


# ---------------- 敌人 buff 权威同步 ----------------

# 归属压制：authority(host) 结算的伤害若归属客机（owner_peer 非本机），不发射本地 enemy_*_proc 全局信号
func _gate_enemy_proc_owner_suppress(damage_data) -> bool:
	if not is_lan_game or not multiplayer.is_server():
		return false
	if damage_data == null or damage_data.get("owner_peer") == null:
		return false
	var op: int = int(damage_data.owner_peer)
	return op != 0 and op != multiplayer.get_unique_id()

# 客机给带 net_id 的敌人镜像加 buff → 转发 host 权威应用；本地不应用（由 host 广播回镜像表现）
func _gate_enemy_buff_apply(manager, buff, value, source_id) -> bool:
	if _applying_remote_buff:
		return false
	if not is_lan_game or multiplayer.is_server():
		return false
	if manager == null or buff == null:
		return false
	if not manager.has_method("_host_kind") or int(manager.call("_host_kind")) != BuffStatMap.ENEMY:
		return false
	var body: Node = manager.get("body")
	if body == null or not is_instance_valid(body) or not body.has_meta("net_id"):
		return false
	rpc_id(1, "_server_apply_enemy_buff", int(body.get_meta("net_id")), str(buff.resource_path), value, str(source_id), _applier_stats())
	return true


# 客机对敌人镜像 apply_conversion_power → 转发 host 权威结算（本端不累积）
func _gate_enemy_conversion(enemy, power) -> bool:
	if not is_lan_game or multiplayer.is_server():
		return false
	if enemy == null or not is_instance_valid(enemy) or not enemy.has_meta("net_id"):
		return false
	rpc_id(1, "_server_enemy_conversion", int(enemy.get_meta("net_id")), int(power))
	return true


@rpc("any_peer", "call_remote", "reliable")
func _server_enemy_conversion(net_id: int, power: int) -> void:
	if not multiplayer.is_server():
		return
	var enemy = enemy_by_net_id.get(net_id)
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.has_method("apply_conversion_power"):
		enemy.call("apply_conversion_power", power)


# 施加者属性快照（DOT 数值/时长以施加者为准）
func _applier_stats() -> Dictionary:
	var p := get_local_player()
	if p == null or p.get("stats") == null:
		return {}
	var st = p.stats
	var out: Dictionary = {}
	if st.get("dot_damage") != null:
		out["dot_damage"] = float(st.get("dot_damage"))
	if st.get("dot_time") != null:
		out["dot_time"] = float(st.get("dot_time"))
	if st.get("global_damage") != null:
		out["global_damage"] = float(st.get("global_damage"))
	if st.get("fire_dot_layer") != null:
		out["fire_dot_layer"] = int(st.get("fire_dot_layer"))
	return out


@rpc("any_peer", "call_remote", "reliable")
func _server_apply_enemy_buff(net_id: int, buff_path: String, value: Array, source_id: String, stats: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var enemy = enemy_by_net_id.get(net_id)
	if enemy == null or not is_instance_valid(enemy):
		return
	var manager = enemy.get("enemy_buff_manager")
	if manager == null:
		return
	var buff = load(buff_path)
	if buff == null:
		return
	# 应用即会触发 _on_enemy_buff_applied（host）→ 统一广播，无需在此再 rpc（避免双播）
	manager.call("apply_buff", buff, value, source_id, stats)


# host 发起的敌人 buff（自然或客机转发）→ 广播客机镜像应用
func _on_enemy_buff_applied(manager, buff, value, source_id, applier_stats, _applier_peer) -> void:
	if _applying_remote_buff:
		return
	if not is_lan_game or not multiplayer.is_server():
		return
	if manager == null or buff == null:
		return
	if not manager.has_method("_host_kind") or int(manager.call("_host_kind")) != BuffStatMap.ENEMY:
		return
	# 策反 buff 不在镜像加 card（视觉由 apply_network_conversion 处理）
	if str(buff.id) == "converted_buff":
		return
	var body = manager.get("body")
	if body == null or not is_instance_valid(body) or not body.has_meta("net_id"):
		return
	rpc("_remote_enemy_buff", int(body.get_meta("net_id")), str(buff.resource_path), value, source_id, applier_stats)


# 客机镜像上应用 buff（仅表现 card；DOT 由本体 _is_remote_mirror 跳过，不结算）
@rpc("authority", "call_remote", "reliable")
func _remote_enemy_buff(net_id: int, buff_path: String, value: Array, source_id: String, stats: Dictionary) -> void:
	if multiplayer.is_server():
		return
	var enemy = enemy_by_net_id.get(net_id)
	if enemy == null or not is_instance_valid(enemy):
		return
	var manager = enemy.get("enemy_buff_manager")
	if manager == null:
		return
	var buff = load(buff_path)
	if buff == null:
		return
	# 策反 buff 镜像不加 card（由 apply_network_conversion 表现）
	if str(buff.id) == "converted_buff":
		return
	_applying_remote_buff = true
	manager.call("apply_buff", buff, value, source_id, stats)
	_applying_remote_buff = false


# host buff 到期/移除 → 广播客机镜像同步移除
func _on_enemy_buff_removed(body: Node, id: String) -> void:
	if not is_lan_game or not multiplayer.is_server():
		return
	if body == null or not is_instance_valid(body) or not body.has_meta("net_id"):
		return
	rpc("_remote_enemy_buff_remove", int(body.get_meta("net_id")), id)


@rpc("authority", "call_remote", "reliable")
func _remote_enemy_buff_remove(net_id: int, id: String) -> void:
	if multiplayer.is_server():
		return
	var enemy = enemy_by_net_id.get(net_id)
	if enemy == null or not is_instance_valid(enemy):
		return
	var manager = enemy.get("enemy_buff_manager")
	if manager == null or manager.get("current_buff") == null:
		return
	if not manager.current_buff.has(id):
		return
	var resource = manager.current_buff[id].get("resource")
	if resource != null:
		manager.call("remove_buff", resource)


# 客户端：敌人受击 → 本地不结算，转交服务端权威处理（返回 true 跳过默认）。
func _intercept_enemy_damage(damage_data, owner) -> bool:
	if not is_lan_game or multiplayer.is_server():
		return false
	if damage_data == null or owner == null:
		return false
	var d := damage_data as DamageData
	if d == null or d.is_heal:
		return false
	if owner.get("faction") == null or int(owner.faction) != Faction.ENEMY_SIDE:
		return false
	if owner.has_meta("coop_owner_net_id"):
		_handle_part_hit(owner, d)
		return true
	if not owner.has_meta("net_id"):
		return false
	var net_id: int = int(owner.get_meta("net_id"))
	d.owner_peer = multiplayer.get_unique_id()
	var predicted: int = _get_predicted_enemy_damage(owner, d.base_damage)
	_replay_hit_feedback(owner, d, predicted, false)
	_predict_enemy_death(owner, predicted, net_id)
	# 本地回放命中闭包（如 poison_ring 的 apply_buff 在此闭包内；host 转发伤害无闭包，不会重复）
	for cb in d.on_damage_dealt:
		if cb is Callable:
			cb.call(owner, d.base_damage)
	# 附带客户端视角的受害者位置，供 host 做轻量回滚合理性校验
	var victim_pos: Vector2 = (owner as Node2D).global_position if owner is Node2D else Vector2.ZERO
	rpc_id(1, "_server_enemy_hit", net_id, _damage_to_dict(d), victim_pos)
	return true


# ---------------- 敌人部件（body_part）同步 ----------------

# 客机命中敌方部件：与根敌人同款即时预测（闪白/乐观扣血/预测碎裂）+ 转发 host 权威结算
func _handle_part_hit(part: Node, data) -> void:
	if part == null or not is_instance_valid(part):
		return
	var d := data as DamageData
	if d == null or d.is_heal:
		return
	if not part.has_meta("coop_owner_net_id"):
		return
	d.owner_peer = multiplayer.get_unique_id()
	var predicted: int = _get_predicted_enemy_damage(part, d.base_damage)
	_replay_hit_feedback(part, d, predicted, false)
	var pstats = part.get("stats")
	if pstats != null:
		var cur: int = int(part.get_meta("predicted_hp", int(pstats.hp)))
		var nhp: int = maxi(0, cur - predicted)
		part.set_meta("predicted_hp", nhp)
		if nhp > 0:
			pstats.hp = nhp
		else:
			part.set_meta("predicted_dead", true)
			pstats.hp = 0
			if part.has_method("idle_state"):
				part.call("idle_state")
	for cb in d.on_damage_dealt:
		if cb is Callable:
			cb.call(part, d.base_damage)
	rpc_id(1, "_server_enemy_part_hit", int(part.get_meta("coop_owner_net_id")), int(part.get_meta("coop_part_index", -1)), _damage_to_dict(d))


# host：把客机对部件的命中应用到真实部件的 HealthComponent（不抑制 → host 原生闪白/受击音 + damage_taken）
@rpc("any_peer", "call_remote", "reliable")
func _server_enemy_part_hit(net_id: int, part_index: int, cfg: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var enemy: Node = enemy_by_net_id.get(net_id)
	if enemy == null or not is_instance_valid(enemy):
		return
	var parts = enemy.get("body_part")
	if parts == null or not (parts is Array) or part_index < 0 or part_index >= parts.size():
		return
	var part: Node = parts[part_index]
	if part == null or not is_instance_valid(part):
		return
	var component: Node = _health_component_of(part)
	if component == null or not component.has_method("take_damage"):
		return
	var d: DamageData = DamageData.fill(null, cfg)
	if d == null:
		return
	d.owner_peer = multiplayer.get_remote_sender_id()
	component.take_damage(d, true, false)


# host：连接敌人各部件的 damage_taken → 广播部件 hp（host 自身 + 客机转发的唯一广播点）
func _connect_enemy_parts(enemy: Node, net_id: int) -> void:
	if not multiplayer.is_server():
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	var parts = enemy.get("body_part")
	if parts == null or not (parts is Array):
		return
	for i in parts.size():
		var part: Node = parts[i]
		if part == null or not is_instance_valid(part):
			continue
		var component: Node = _health_component_of(part)
		if component == null or not component.has_signal("damage_taken"):
			continue
		var cb := Callable(self, "_on_server_enemy_part_damage_taken").bind(enemy, net_id, i)
		if not component.damage_taken.is_connected(cb):
			component.damage_taken.connect(cb)


# 给敌人各 body_part 打标记（客机拦截器据此识别"这是部件镜像"并转发到对应敌人）
func _tag_enemy_parts(enemy: Node, net_id: int) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var parts = enemy.get("body_part")
	if parts == null or not (parts is Array):
		return
	for i in parts.size():
		var part = parts[i]
		if part == null or not is_instance_valid(part):
			continue
		part.set_meta("coop_owner_net_id", net_id)
		part.set_meta("coop_part_index", i)


func _on_server_enemy_part_damage_taken(actual_damage: int, _data, enemy: Node, net_id: int, part_index: int) -> void:
	if not multiplayer.is_server():
		return
	if actual_damage <= 0:
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	var parts = enemy.get("body_part")
	if parts == null or not (parts is Array) or part_index < 0 or part_index >= parts.size():
		return
	var part: Node = parts[part_index]
	if part == null or not is_instance_valid(part) or part.get("stats") == null:
		return
	rpc("_remote_enemy_part_hp", net_id, part_index, int(part.stats.hp), true)


# 收集敌人各部件当前 hp（-1 表示该部件无 stats），用于晚加入一次性下发
func _enemy_part_hps(enemy: Node) -> PackedInt32Array:
	var out := PackedInt32Array()
	if enemy == null or not is_instance_valid(enemy):
		return out
	var parts = enemy.get("body_part")
	if parts == null or not (parts is Array):
		return out
	for part in parts:
		if part == null or not is_instance_valid(part) or part.get("stats") == null:
			out.append(-1)
		else:
			out.append(int(part.stats.hp))
	return out


# 开发/测试探针：部件 hp 广播应用次数 / 部件闪白应用次数
var _dev_part_hp_applied: int = 0
var _dev_part_flash_applied: int = 0

func dev_part_stats() -> Dictionary:
	return {"hp_applied": _dev_part_hp_applied, "flash_applied": _dev_part_flash_applied}


# 客机镜像应用部件权威 hp：校正预测 + 撤销/触发预测碎裂 + 闪白
@rpc("authority", "call_remote", "reliable")
func _remote_enemy_part_hp(net_id: int, part_index: int, hp: int, flash: bool) -> void:
	if multiplayer.is_server():
		return
	var enemy: Node = enemy_by_net_id.get(net_id)
	if enemy == null or not is_instance_valid(enemy):
		return
	var parts = enemy.get("body_part")
	if parts == null or not (parts is Array) or part_index < 0 or part_index >= parts.size():
		return
	var part: Node = parts[part_index]
	if part == null or not is_instance_valid(part) or part.get("stats") == null:
		return
	_dev_part_hp_applied += 1
	part.set_meta("predicted_hp", hp)
	if part.get_meta("predicted_dead", false) and hp > 0:
		part.set_meta("predicted_dead", false)
		if part.has_method("active_state"):
			part.call("active_state")
	if hp <= 0:
		part.set_meta("predicted_dead", true)
		part.stats.hp = 0
		if part.has_method("idle_state"):
			part.call("idle_state")
	else:
		part.stats.hp = hp
		if flash and part.has_method("_hurt_flash") and remote_flash_allowed(part):
			part.call("_hurt_flash")
			_dev_part_flash_applied += 1


func _gate_coin_pickup(coin, player, coin_mult) -> bool:
	if not is_lan_game:
		return false
	if coin == null or player == null or coin.get("coin") == null:
		return false
	var value: int = int(ceil(float(coin.coin) * float(coin_mult)))
	var pos: Vector2 = coin.global_position
	var net_id: int = int(coin.get_meta("net_id")) if coin.has_meta("net_id") else -1
	if multiplayer.is_server():
		_do_shared_coin_pickup(net_id, value, pos, coin)
	else:
		rpc_id(1, "_server_pickup_coin", net_id, value, pos)
	return true


func _gate_player_death(player) -> bool:
	if not is_lan_game:
		return false
	if player == null or player != get_local_player():
		return false
	if player.has_method("set_downed_state"):
		player.set_downed_state(true)
	return true


func _gate_game_over(player_dead: bool) -> bool:
	if not is_lan_game:
		return false
	# LAN 下 emit_game_over 仅来自「暂停投降/主动结束」（玩家死亡由 player_death_gate 单独接管）
	# → 一律按团队结束处理（host 权威；client 转交 host）
	if multiplayer.is_server():
		_force_team_game_over_authoritative(player_dead)
	else:
		rpc_id(1, "_server_request_team_game_over", player_dead)
	return true


func _on_round_start() -> void:
	round_upgrade_ready_peers.clear()


# 升级开始时由 host 统一复活所有倒地队友（对齐联机版），并广播 round_upgrade 让客机展示升级页
func _on_round_upgrade() -> void:
	if not is_lan_game or not multiplayer.is_server():
		return
	_revive_all_downed_for_upgrade()
	if not _is_test_room():
		rpc("_remote_round_upgrade")


# host 回合结束 → 广播给客机（客机清场；转场/升级等 host 的 round_upgrade 广播）
func _on_local_round_end() -> void:
	if not is_lan_game or not multiplayer.is_server():
		return
	if _is_test_room():
		return
	rpc("_remote_round_end")


# 客机：本端不自发 round_end（由 host 广播驱动）
func _gate_round_end_emit() -> bool:
	return is_lan_game and not multiplayer.is_server()


# 客机：清场后不本地转场/升级（等 host 的 _remote_round_upgrade）
func _gate_round_end_proceed() -> bool:
	return is_lan_game and not multiplayer.is_server()


# 联机客机不本地刷怪（敌人由 host 权威 + 镜像）
func _gate_round_enemy_spawn() -> bool:
	return is_lan_game and not multiplayer.is_server()


# ---------------- 角色专属事件（一次性表现） ----------------

func _on_character_event(player: Node, event_name: StringName, event_data: Dictionary) -> void:
	if not is_lan_game or player == null or event_name == &"":
		return
	if player != get_local_player():
		return
	var pid: int = multiplayer.get_unique_id()
	if multiplayer.is_server():
		rpc("_remote_character_event", pid, String(event_name), event_data)
	else:
		rpc_id(1, "_server_character_event", String(event_name), event_data)


@rpc("any_peer", "call_remote", "reliable")
func _server_character_event(event_name: String, event_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_apply_character_event(sender, event_name, event_data)
	rpc("_remote_character_event", sender, event_name, event_data)


@rpc("authority", "call_remote", "reliable")
func _remote_character_event(peer_id: int, event_name: String, event_data: Dictionary) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	_apply_character_event(peer_id, event_name, event_data)


func _apply_character_event(peer_id: int, event_name: String, event_data: Dictionary) -> void:
	var p = player_by_peer_id.get(peer_id)
	if p == null or not is_instance_valid(p):
		return
	if p.has_method("apply_network_character_event"):
		p.call("apply_network_character_event", StringName(event_name), event_data)


func dev_character_event_probe() -> void:
	var p := get_local_player()
	if p != null and p.has_method("broadcast_character_event"):
		p.call("broadcast_character_event", &"dev_probe", {"n": 1})
		print("[etn_coop] dev_character_event_probe sent local=%s" % str(multiplayer.get_unique_id()))


func dev_motion_probe() -> void:
	_show_motion_down()
	await get_tree().create_timer(1.5, true, false, true).timeout
	_hide_motion_down()
	print("[etn_coop] dev_motion_probe done local=%s time_scale=%s" % [str(multiplayer.get_unique_id()), str(Engine.time_scale)])


@rpc("authority", "call_remote", "reliable")
func _remote_round_end() -> void:
	if multiplayer.is_server():
		return
	GameEvents.emit_round_end()


@rpc("authority", "call_remote", "reliable")
func _remote_round_upgrade() -> void:
	if multiplayer.is_server():
		return
	GameEvents.emit_round_upgrade()
	GameEvents.emit_player_buff_clear()
	get_tree().paused = true


func _is_test_room() -> bool:
	return current_scene_path.contains("test_room")


func _revive_all_downed_for_upgrade() -> void:
	var targets: Array = down_peer_ids.keys()
	for pid in targets:
		var target: int = int(pid)
		down_peer_ids.erase(target)
		rpc("_remote_revived", target, 1.0)
		_apply_revive_local(target, 1.0)


func _gate_round_upgrade_end() -> bool:
	if not is_lan_game:
		return false
	var pid: int = multiplayer.get_unique_id()
	round_upgrade_ready_peers[pid] = true
	if multiplayer.is_server():
		rpc("_remote_round_upgrade_ready_changed", pid, true)
		_maybe_finish_round_upgrade()
	else:
		rpc_id(1, "_server_round_upgrade_ready")
	return true


# ---------------- 通知类（骨架：占位） ----------------

func _on_projectile_spawned(bullet: Node, _owner: Node, _source_faction: int) -> void:
	if not is_lan_game or bullet == null or not is_instance_valid(bullet):
		return
	if bullet.has_meta("remote_visual"):
		return
	# 标记：ProjectileSpawner 已广播，child_entered_tree 的通用视觉广播不再重复
	bullet.set_meta("_coop_ps_broadcast", true)
	var scene_path: String = bullet.scene_file_path
	if scene_path == "":
		return
	# 无 velocity → 爆炸/范围/一次性特效，走特效通道（纯表现）
	if bullet.get("velocity") == null:
		var props: Dictionary = {}
		for pname in EFFECT_PROP_NAMES:
			var v = bullet.get(pname)
			if v != null:
				props[pname] = v
		_pending_effects.append({
			"s": scene_path,
			"p": bullet.global_position,
			"r": bullet.global_rotation,
			"sc": bullet.scale,
			"g": _root_group_of(bullet),
			"m": "active_state",
			"pr": props,
		})
		return
	var sync_id: String = "%d_%d" % [multiplayer.get_unique_id(), _next_visual_id]
	_next_visual_id += 1
	bullet.set_meta("net_visual_id", sync_id)
	var spd: float = 0.0
	if bullet.get("speed") != null:
		spd = float(bullet.speed)
	var kt: int = 0
	if bullet.get("kill_time") != null:
		kt = int(bullet.kill_time)
	var bprops: Dictionary = {}
	for pname in BULLET_PROP_NAMES:
		var v = bullet.get(pname)
		if v != null:
			bprops[pname] = v
	var entry: Dictionary = {
		"s": scene_path,
		"p": bullet.global_position,
		"r": bullet.global_rotation,
		"sc": bullet.scale,
		"sp": spd,
		"k": kt,
		"id": sync_id,
		"eb": _source_faction == Faction.ENEMY_SIDE,
		"dmg": int(bullet.damage_data.base_damage) if bullet.get("damage_data") != null else 1,
		"kb": int(bullet.damage_data.knockback_force) if bullet.get("damage_data") != null else 0,
		"pr": bprops,
		"pre": "",
		"m": "active_state",
	}
	# 一次性关键投射物（由生成方打 coop_reliable_visual meta）→ 可靠通道
	if bullet.has_meta("coop_reliable_visual"):
		_pending_visual_reliable.append(entry)
	else:
		_pending_visual.append(entry)


func _root_group_of(node: Node) -> String:
	var p := node.get_parent()
	if p == null:
		return "SELayer"
	for g in p.get_groups():
		var gs: String = String(g)
		if gs in ["SELayer", "BulletRoot", "ForegroundLayer", "FloorLayer", "PlayerRoot", "EnemiesRoot", "EquipLayer"]:
			return gs
	return "SELayer"


func _on_projectile_despawned(bullet: Node) -> void:
	if not is_lan_game or bullet == null or not is_instance_valid(bullet):
		return
	if bullet.has_meta("remote_visual"):
		if bullet.has_meta("visual_sync_id"):
			_visual.forget(str(bullet.get_meta("visual_sync_id")))
			bullet.remove_meta("visual_sync_id")
		bullet.remove_meta("remote_visual")
		return
	if bullet.has_meta("net_visual_id"):
		var sync_id: String = str(bullet.get_meta("net_visual_id"))
		bullet.remove_meta("net_visual_id")
		if multiplayer.is_server():
			rpc("_despawn_visual_bullet", sync_id)
		else:
			rpc_id(1, "_server_despawn_visual_bullet", sync_id)


# ---------------- 命中表现按来源广播（拥有者产出，其它端复刻） ----------------

# 玩家子弹命中敌人瞬间（拥有者）→ 按子弹类型广播对应子弹烟给其它端。
# HurtSounds 不在此播（由 _replay_hit_feedback 统一处理，含 host/观察者）。
func _on_any_projectile_hit(bullet: Node, _hit_body: Node) -> void:
	if not is_lan_game or bullet == null or not is_instance_valid(bullet):
		return
	if bullet.has_meta("remote_visual"):
		return
	var scene_path: String = ""
	if bullet is PlayerMortarBullet:
		return
	elif bullet is PlayerBullet:
		scene_path = "res://scenes/bullet/bullet_smoke.tscn"
	elif bullet is SummonedBullet:
		scene_path = "res://scenes/bullet/bullet_smoke_2.tscn"
	else:
		return
	_pending_effects.append({
		"s": scene_path,
		"p": bullet.global_position,
		"r": 0.0,
		"sc": Vector2.ONE,
		"g": "SELayer",
		"m": "smoke_anim",
		"pr": {},
	})


# 爆炸视觉/音效触发（拥有者）→ 广播大/小爆炸 VFX + ExplosionSounds 给其它端
func _on_explosion_effect(position: Vector2, is_big: bool) -> void:
	if not is_lan_game:
		return
	var scene_path: String = "res://script/explosion.tscn" if is_big else "res://script/small_explosion.tscn"
	_pending_effects.append({
		"s": scene_path,
		"p": position,
		"r": 0.0,
		"sc": Vector2.ONE,
		"g": "SELayer",
		"m": "active_state",
		"pr": {},
	})
	_broadcast_hit_sfx("ExplosionSounds")


# 命中额外音效（拥有者，如近战 HurtSounds2）→ 广播给其它端
func _on_hit_sfx(sfx_key: String, _position: Vector2) -> void:
	if not is_lan_game or sfx_key == "":
		return
	_broadcast_hit_sfx(sfx_key)


func _broadcast_hit_sfx(sfx_key: String) -> void:
	if multiplayer.is_server():
		rpc("_remote_hit_sfx", sfx_key)
	else:
		rpc_id(1, "_server_hit_sfx", sfx_key)


@rpc("any_peer", "call_remote", "unreliable")
func _server_hit_sfx(sfx_key: String) -> void:
	if not multiplayer.is_server():
		return
	# host 自己也播一次（受远端限流）
	_remote_hit_sfx(sfx_key)
	var sender: int = multiplayer.get_remote_sender_id()
	for peer in multiplayer.get_peers():
		if peer != sender:
			rpc_id(peer, "_remote_hit_sfx", sfx_key)


@rpc("authority", "call_remote", "unreliable")
func _remote_hit_sfx(sfx_key: String) -> void:
	if not is_lan_game:
		return
	if _remote_sfx_allowed(sfx_key):
		SoundManager.play_sfx(sfx_key)


# 远端命中音限流：每 key 间隔 + 全局最小间隔；mult 复用「远端效果频率」档位（0=关远端命中音）
func _remote_sfx_allowed(sfx_key: String) -> bool:
	var mult: int = _freq_mult(settings.remote_effect_freq)
	if mult <= 0:
		return false
	var now: int = Time.get_ticks_msec()
	if now - _remote_sfx_last_global_ms < REMOTE_HITSFX_GLOBAL_MIN_MS:
		return false
	var interval: int = int(round(float(REMOTE_HITSFX_KEY_BASE_MS) / float(max(1, mult))))
	if now - int(_remote_sfx_last_ms.get(sfx_key, -1000000000)) < interval:
		return false
	_remote_sfx_last_ms[sfx_key] = now
	_remote_sfx_last_global_ms = now
	return true


# ---------------- 池化视觉节点「每次激活」广播 ----------------

# 节点建一次后靠 active_state 复用的道具特效（镰刀/火场/毒环/冰环）：child_entered_tree 只首次触发，
# 故在激活点显式广播（走 _remote_visual_node，接收端 spawn_visual_effect 纯视觉）
func _on_visual_activated(node: Node) -> void:
	if not is_lan_game or node == null or not is_instance_valid(node):
		return
	if node.has_meta("remote_visual") or node.has_meta("net_visual_id") or node.has_meta("coop_action_flash"):
		return
	# 标记已由本通道广播，避免同帧 child_entered_tree 的通用广播重复
	node.set_meta("_coop_visual_broadcast", true)
	var scene_path: String = str(node.scene_file_path)
	if scene_path == "":
		return
	var par := node.get_parent()
	if par == null:
		return
	var grp: String = _layer_group_of(par)
	if grp == "":
		return
	var pos := Vector2.ZERO
	var rot := 0.0
	var sc := Vector2.ONE
	if node is Node2D:
		pos = (node as Node2D).global_position
		rot = (node as Node2D).global_rotation
		sc = (node as Node2D).scale
	var method: String = "active_state" if node.has_method("active_state") else ""
	if multiplayer.is_server():
		rpc("_remote_visual_node", scene_path, pos, rot, sc, grp, method)
	else:
		rpc_id(1, "_server_visual_node", scene_path, pos, rot, sc, grp, method)


# 拾取物生成（pyroxenes 等）→ 广播纯视觉副本
func _on_pickup_spawned(node: Node) -> void:
	_on_visual_activated(node)


func _on_enemy_spawned(enemy_body: Node, scene_path: String) -> void:
	if not is_lan_game or not multiplayer.is_server():
		return
	register_enemy_spawn(enemy_body, scene_path)


func _on_summoned_spawned(summoned: Node, scene_path: String) -> void:
	if not is_lan_game or summoned == null or not is_instance_valid(summoned):
		return
	if summoned.has_meta("remote_summoned"):
		return
	var pos: Vector2 = summoned.global_position
	var rot: float = summoned.global_rotation
	if multiplayer.is_server():
		# host 统一分配 net_id
		var net_id: int = next_summoned_net_id
		next_summoned_net_id += 1
		_register_local_summoned(summoned, net_id, multiplayer.get_unique_id(), scene_path)
		for peer in multiplayer.get_peers():
			rpc_id(peer, "_spawn_summoned_remote", net_id, multiplayer.get_unique_id(), scene_path, pos, rot)
	else:
		# client：先本地生成，等 host 分配 net_id 后认领（pending_local_summons）
		pending_local_summons.append({"node": summoned, "scene": scene_path})
		rpc_id(1, "_server_register_summoned", scene_path, pos, rot)


func _register_local_summoned(summoned: Node, net_id: int, owner_peer: int, scene_path: String) -> void:
	summoned_by_net_id[net_id] = summoned
	summoned_scene_by_net_id[net_id] = scene_path
	summoned_owner_by_net_id[net_id] = owner_peer
	_attach_summoned_proxy(summoned, net_id, owner_peer, owner_peer == multiplayer.get_unique_id())


@rpc("any_peer", "call_remote", "reliable")
func _server_register_summoned(scene_path: String, position: Vector2, rotation: float) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	var net_id: int = next_summoned_net_id
	next_summoned_net_id += 1
	# host 侧生成镜像
	_spawn_summoned_local(net_id, sender, scene_path, position, rotation)
	# 广播给所有端（含发送者，用于认领本地实体）
	for peer in multiplayer.get_peers():
		rpc_id(peer, "_spawn_summoned_remote", net_id, sender, scene_path, position, rotation)


func _consume_pending_local_summon(scene_path: String) -> Node:
	for i in pending_local_summons.size():
		var entry: Dictionary = pending_local_summons[i]
		if str(entry["scene"]) == scene_path:
			var node = entry["node"]
			pending_local_summons.remove_at(i)
			if node != null and is_instance_valid(node):
				return node
			return null
	return null


func _on_summoned_despawned(_summoned: Node) -> void:
	# despawn 由 proxy 的 idle 检测统一走 request_summoned_despawn，这里不重复广播
	pass


# ---------------- 召唤物/道具动作（开火等）同步 ----------------

# 拥有者触发（如炮台开火）→ 广播给其它端复刻（后坐动画 + 炮口闪光 + 音效）
func _on_summoned_action(summoned: Node, action: String, sfx_key: String, fx_scene: String, fx_pos: Vector2, fx_rot: float, action_dur: float = 0.0) -> void:
	if not is_lan_game or summoned == null or not is_instance_valid(summoned):
		return
	if not summoned.has_meta("summoned_net_id"):
		return
	var net_id: int = int(summoned.get_meta("summoned_net_id"))
	if multiplayer.is_server():
		rpc("_remote_summoned_action", net_id, action, sfx_key, fx_scene, fx_pos, fx_rot, action_dur)
	else:
		rpc_id(1, "_server_summoned_action", net_id, action, sfx_key, fx_scene, fx_pos, fx_rot, action_dur)


@rpc("any_peer", "call_remote", "reliable")
func _server_summoned_action(net_id: int, action: String, sfx_key: String, fx_scene: String, fx_pos: Vector2, fx_rot: float, action_dur: float = 0.0) -> void:
	if not multiplayer.is_server():
		return
	# host 本地也要应用（它持有客机召唤物的镜像）
	_remote_summoned_action(net_id, action, sfx_key, fx_scene, fx_pos, fx_rot, action_dur)
	var sender: int = multiplayer.get_remote_sender_id()
	for peer in multiplayer.get_peers():
		if peer != sender:
			rpc_id(peer, "_remote_summoned_action", net_id, action, sfx_key, fx_scene, fx_pos, fx_rot, action_dur)


@rpc("authority", "call_remote", "reliable")
func _remote_summoned_action(net_id: int, action: String, sfx_key: String, fx_scene: String, fx_pos: Vector2, fx_rot: float, action_dur: float = 0.0) -> void:
	if not is_lan_game:
		return
	var node = summoned_by_net_id.get(net_id)
	if node != null and is_instance_valid(node) and node.has_method("network_play_action"):
		node.call("network_play_action", action, action_dur)
	if fx_scene != "":
		_visual.spawn_visual_effect(get_tree(), fx_scene, fx_pos, fx_rot, Vector2.ONE, "SELayer", "active_state", {})
	if sfx_key != "":
		_remote_hit_sfx(sfx_key)


func _on_coin_spawned(coin: Node, value: int) -> void:
	if not is_lan_game or not multiplayer.is_server():
		return
	if coin == null or not is_instance_valid(coin) or value <= 0:
		return
	var net_id: int = next_coin_net_id
	next_coin_net_id += 1
	coin.set_meta("net_id", net_id)
	coin_by_net_id[net_id] = coin
	rpc("_spawn_coin_remote", net_id, coin.global_position, int(coin.coin), bool(coin.pick_up))


func _on_player_downed(player: Node) -> void:
	if not is_lan_game:
		return
	if player != get_local_player():
		return
	var pid: int = multiplayer.get_unique_id()
	down_peer_ids[pid] = true
	_show_motion_down()
	if multiplayer.is_server():
		rpc("_remote_player_down_changed", pid, true)
		_check_team_game_over()
	else:
		rpc_id(1, "_server_player_down")


func _on_player_revived(player: Node) -> void:
	if not is_lan_game:
		return
	if player != get_local_player():
		return
	var pid: int = multiplayer.get_unique_id()
	down_peer_ids.erase(pid)
	_hide_motion_down()
	if multiplayer.is_server():
		rpc("_remote_player_down_changed", pid, false)
	else:
		rpc_id(1, "_server_player_up")


# ---------------- 本地倒地全屏表现（灰度遮罩 + 短暂慢动作） ----------------

var _motion = null


func _ensure_motion() -> void:
	if _motion != null and is_instance_valid(_motion):
		return
	var t := get_tree()
	if t == null:
		return
	_motion = MotionDownScript.new()
	_motion.name = "CoopMotionDown"
	t.root.add_child(_motion)


func _show_motion_down() -> void:
	_ensure_motion()
	if _motion != null and is_instance_valid(_motion):
		_motion.call("show_down")


func _hide_motion_down() -> void:
	if _motion != null and is_instance_valid(_motion):
		_motion.call("hide_down")


# ---------------- 角色事件（近战 / 换弹） ----------------

func _on_player_melee(player: Node, animation_name: String) -> void:
	if not is_lan_game:
		return
	if player != get_local_player():
		return
	if multiplayer.is_server():
		rpc("_remote_player_melee", multiplayer.get_unique_id(), animation_name)
	else:
		rpc_id(1, "_server_player_melee", animation_name)


@rpc("any_peer", "call_remote", "reliable")
func _server_player_melee(animation_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	rpc("_remote_player_melee", sender, animation_name)
	_remote_player_melee(sender, animation_name)


@rpc("authority", "call_remote", "reliable")
func _remote_player_melee(peer_id: int, animation_name: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var p = player_by_peer_id.get(peer_id)
	if p == null or not is_instance_valid(p):
		return
	var ka = p.get("kick_anim")
	if ka != null and ka.has_method("play"):
		ka.call("play", animation_name)


func _on_player_reload(gun_node: Node, animation_name: String, speed_scale: float) -> void:
	if not is_lan_game:
		return
	if multiplayer.is_server():
		rpc("_remote_player_reload", multiplayer.get_unique_id(), animation_name, speed_scale)
	else:
		rpc_id(1, "_server_player_reload", animation_name, speed_scale)


@rpc("any_peer", "call_remote", "reliable")
func _server_player_reload(animation_name: String, speed_scale: float) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	rpc("_remote_player_reload", sender, animation_name, speed_scale)
	_remote_player_reload(sender, animation_name, speed_scale)


@rpc("authority", "call_remote", "reliable")
func _remote_player_reload(peer_id: int, animation_name: String, speed_scale: float) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var p = player_by_peer_id.get(peer_id)
	if p == null or not is_instance_valid(p):
		return
	var gun = p.get("gun")
	if gun == null:
		return
	var ra = gun.get("reload_anim")
	if ra != null and ra.has_method("play"):
		ra.speed_scale = speed_scale
		ra.call("play", animation_name)
	var rs = gun.get("reload_sounds")
	if rs != null and rs.has_method("play"):
		rs.call("play")


# ---------------- pyroxenes 共享 ----------------

func _on_pyroxenes_gain(amount: int) -> void:
	if not is_lan_game or amount <= 0:
		return
	if multiplayer.is_server():
		for peer in multiplayer.get_peers():
			rpc_id(peer, "_apply_shared_pyroxenes_remote", amount)
	else:
		rpc_id(1, "_server_shared_pyroxenes_gain", amount)


@rpc("any_peer", "call_remote", "reliable")
func _server_shared_pyroxenes_gain(amount: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_apply_shared_pyroxenes_local(amount)
	for peer in multiplayer.get_peers():
		if int(peer) != sender:
			rpc_id(peer, "_apply_shared_pyroxenes_remote", amount)


@rpc("authority", "call_remote", "reliable")
func _apply_shared_pyroxenes_remote(amount: int) -> void:
	_apply_shared_pyroxenes_local(amount)


func _apply_shared_pyroxenes_local(amount: int) -> void:
	PlayerData.player_pyroxenes += amount
	# 非拾取端补发拾取事件（boss 回合结束依赖 pyroxenes_pick_up）
	GameEvents.emit_pyroxenes_pick_up()


# ---------------- 本地换人（对齐联机版 request_local_player_change） ----------------

func _gate_local_player_change(path: String, position: Vector2) -> bool:
	if not is_lan_game or path == "":
		return false
	request_local_player_change(path, position)
	return true


# ---------------- 暂停菜单语义（对齐联机版：LAN 只停本地玩家，不暂停世界） ----------------

func _is_lan_session() -> bool:
	return is_lan_game


func _on_pause_visibility(visible: bool, pause_screen: Node) -> void:
	if not is_lan_game:
		# 单机：保持本体行为
		get_tree().paused = visible
		return
	# LAN：只冻结本地玩家；世界继续跑；暂停菜单始终可操作
	if pause_screen is Node and int(pause_screen.get("process_mode")) != Node.PROCESS_MODE_ALWAYS:
		pause_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	var p := get_local_player()
	if p != null and is_instance_valid(p):
		p.set_deferred("player_stop", visible)
		p.set_meta("pause_menu_open", visible)
	_update_pause_room_label(visible, pause_screen)


# 关卡内暂停页显示房号（深色面板 + 白字 + 深绿描边），位置在 LANGUAGE 下拉下方
func _update_pause_room_label(paused: bool, pause_screen: Node) -> void:
	if pause_screen == null or not is_instance_valid(pause_screen):
		return
	var text := get_room_display_text()
	if text == "":
		if _pause_room_panel != null and is_instance_valid(_pause_room_panel):
			_pause_room_panel.visible = false
		return
	if _pause_room_panel == null or not is_instance_valid(_pause_room_panel):
		_build_pause_room_label(pause_screen)
	if _pause_room_panel == null or not is_instance_valid(_pause_room_panel):
		return
	if _pause_room_label != null and is_instance_valid(_pause_room_label):
		_pause_room_label.text = text
	_pause_room_panel.visible = paused


func _build_pause_room_label(pause_screen: Node) -> void:
	var anchor := pause_screen.get_node_or_null("Node2D10/Node2D9/langue_button")
	var parent: Node = pause_screen
	var pos := Vector2(-27, 16)
	if anchor is Node2D:
		parent = anchor.get_parent()
		pos = (anchor as Node2D).position + Vector2(0, PAUSE_ROOM_OFFSET_Y)
	_pause_room_panel = PanelContainer.new()
	_pause_room_panel.name = "CoopPauseRoom"
	_pause_room_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_room_panel.position = pos
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	_pause_room_panel.add_theme_stylebox_override("panel", style)
	_pause_room_label = Label.new()
	_pause_room_label.add_theme_font_override("font", RoomFont)
	_pause_room_label.add_theme_font_size_override("font_size", 10)
	_pause_room_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_pause_room_label.add_theme_color_override("font_outline_color", Color(0.03, 0.28, 0.10, 1))
	_pause_room_label.add_theme_constant_override("outline_size", 4)
	_pause_room_panel.add_child(_pause_room_label)
	parent.add_child(_pause_room_panel)


func request_local_player_change(path: String, position: Vector2) -> void:
	if not is_lan_game or path == "":
		return
	if position == Vector2.ZERO:
		var p := get_local_player()
		if p is Node2D:
			position = (p as Node2D).global_position
	if multiplayer.is_server():
		var local_id: int = multiplayer.get_unique_id()
		_replace_player_for_peer(local_id, path, position)
		rpc("_replace_player_remote", local_id, path, position)
	else:
		rpc_id(1, "_server_request_player_change", path, position)


@rpc("any_peer", "call_remote", "reliable")
func _server_request_player_change(path: String, position: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_replace_player_for_peer(sender, path, position)
	rpc("_replace_player_remote", sender, path, position)


@rpc("authority", "call_remote", "reliable")
func _replace_player_remote(peer_id: int, path: String, position: Vector2) -> void:
	_replace_player_for_peer(peer_id, path, position)


func _replace_player_for_peer(peer_id: int, path: String, position: Vector2) -> void:
	if path == "":
		return
	var local_id: int = multiplayer.get_unique_id()
	if peer_id == local_id:
		var old := get_local_player()
		if old != null and is_instance_valid(old):
			old.queue_free()
		var root := get_tree().get_first_node_in_group("PlayerRoot")
		if root == null:
			return
		var scene := load(path) as PackedScene
		if scene == null:
			return
		var p: Node = scene.instantiate()
		p.set_meta("peer_id", peer_id)
		root.add_child(p)
		if p is Node2D:
			(p as Node2D).global_position = position
		player_scene_by_peer[peer_id] = path
		_ensure_local_proxy(p)
		_attach_name_tag(p, peer_id)
		PlayerData.player = p
		# 换人后本机 PlayerRoot 可能刚被 test_room 重置清过，补生远端镜像
		_schedule_respawn_remotes()
	else:
		var old_remote = player_by_peer_id.get(peer_id)
		if old_remote != null and is_instance_valid(old_remote):
			old_remote.queue_free()
		player_by_peer_id.erase(peer_id)
		player_proxy_by_peer_id.erase(peer_id)
		player_scene_by_peer[peer_id] = path
		_clear_peer_item_visuals(peer_id)
		spawn_remote_player(peer_id, path)
		var np = player_by_peer_id.get(peer_id)
		if np is Node2D:
			(np as Node2D).global_position = position


# ---------------- 道具常驻视觉（EquipItem 图标）同步 ----------------
# 约定：道具图标为 res://scenes/update_item/<id>_icon.tscn（follow_icon.gd），挂到玩家 Follow 标记。
# 拥有者本机由道具自身 _on_equip 生成；本函数只让"非拥有者"端为镜像补一个纯视觉图标。

var item_visual_by_peer: Dictionary = {}   # owner_peer -> Array[Node]

func _on_local_ability_upgrade_added(upgrade, _current_upgrade) -> void:
	if not is_lan_game or upgrade == null:
		return
	rpc("_remote_item_visual", multiplayer.get_unique_id(), str(upgrade.id))


# 非拥有者端：为远端镜像复刻道具视觉（纯视觉）。
# RPC 用 any_peer：图标为纯视觉、无权威状态；接收端已按 owner_peer==self 去重。
# 视觉清单在 CoopItemVisuals（本体无 upgrade→视觉 数据源，故枚举）。
@rpc("any_peer", "call_remote", "reliable")
func _remote_item_visual(owner_peer: int, item_id: String) -> void:
	if owner_peer == multiplayer.get_unique_id():
		return
	var mirror = player_by_peer_id.get(owner_peer)
	if mirror == null or not is_instance_valid(mirror):
		return
	var visual: Node = ItemVisuals.build_icon(get_tree(), mirror, item_id)
	if visual == null:
		visual = ItemVisuals.build_internal_visual(mirror, item_id)
	if visual == null:
		print("[etn_coop] item-visual peer=%d id=%s none" % [owner_peer, item_id])
		return
	print("[etn_coop] item-visual peer=%d id=%s node=%s" % [owner_peer, item_id, visual.name])
	if not item_visual_by_peer.has(owner_peer):
		item_visual_by_peer[owner_peer] = []
	item_visual_by_peer[owner_peer].append(visual)


func _clear_item_visuals() -> void:
	for arr in item_visual_by_peer.values():
		for icon in arr:
			if icon != null and is_instance_valid(icon):
				icon.queue_free()
	item_visual_by_peer.clear()
	for peer_id in player_by_peer_id.keys():
		var m = player_by_peer_id[peer_id]
		if m != null and is_instance_valid(m):
			m.remove_meta("coop_last_follow_icon")


# 只清某玩家的道具视觉（换角色时旧镜像被释放，挂到 PlayerRoot 的 follow 图标不会随之释放，需单独清）
func _clear_peer_item_visuals(peer_id: int) -> void:
	var mirror = player_by_peer_id.get(peer_id)
	if mirror != null and is_instance_valid(mirror):
		mirror.remove_meta("coop_last_follow_icon")
	var arr = item_visual_by_peer.get(peer_id)
	if arr == null:
		return
	for icon in arr:
		if icon != null and is_instance_valid(icon):
			icon.queue_free()
	item_visual_by_peer.erase(peer_id)


# 本机测试房重置/换角色：本体 reset_clear_unit 已清本机 PlayerRoot 非"Player"（含远端镜像）
# 与本地召唤物/特效；这里重同步并只清本机拥有的召唤物（对端镜像）
func _on_local_test_room_reset() -> void:
	if not is_lan_game:
		return
	_schedule_respawn_remotes()
	_hook_visual_roots()
	if multiplayer.is_server():
		_respawn_remote_players()
	else:
		rpc_id(1, "_client_scene_ready")
	_despawn_owned_summons_local()
	_clear_item_visuals()


# 只清"本机拥有"的召唤物：清本地记录并通知对端移除镜像（其它玩家的召唤物镜像不动）
func _despawn_owned_summons_local() -> void:
	var local_id: int = multiplayer.get_unique_id()
	var to_remove: Array = []
	for k in summoned_owner_by_net_id.keys():
		if int(summoned_owner_by_net_id[k]) == local_id:
			to_remove.append(int(k))
	for net_id in to_remove:
		summoned_by_net_id.erase(net_id)
		summoned_proxy_by_net_id.erase(net_id)
		summoned_scene_by_net_id.erase(net_id)
		summoned_owner_by_net_id.erase(net_id)
		rpc("_despawn_summoned_remote", net_id)


# ---------------- 道具生成视觉节点的通用广播（child_entered_tree，覆盖 murky scythe 等直接 add_child） ----------------
var _visual_roots_hooked: Dictionary = {}

func _hook_visual_roots() -> void:
	for grp in ["SELayer", "ForegroundLayer", "BulletRoot", "EquipLayer", "FloorLayer", "PlayerRoot"]:
		var root := get_tree().get_first_node_in_group(grp)
		if root != null and not _visual_roots_hooked.has(root):
			_visual_roots_hooked[root] = true
			if not root.child_entered_tree.is_connected(_on_visual_root_child_entered):
				root.child_entered_tree.connect(_on_visual_root_child_entered)

func _on_visual_root_child_entered(child: Node) -> void:
	if not is_lan_game:
		return
	# 延迟一帧：等 ProjectileSpawner 的 _on_projectile_spawned 打完 _coop_ps_broadcast 标记再判定
	_maybe_broadcast_visual_node.call_deferred(child)

func _layer_group_of(par: Node) -> String:
	for grp in ["SELayer", "ForegroundLayer", "BulletRoot", "EquipLayer", "FloorLayer", "PlayerRoot", "CoinRoot"]:
		if par.is_in_group(grp):
			return grp
	return ""

func _maybe_broadcast_visual_node(child: Node) -> void:
	if child == null or not is_instance_valid(child):
		return
	if child.has_meta("remote_visual") or child.has_meta("net_visual_id") or child.has_meta("_coop_ps_broadcast") or child.has_meta("_coop_visual_broadcast"):
		return
	# 召唤物开火闪光由 _on_summoned_action 统一广播，跳过 SELayer 通用广播避免重复
	if child.has_meta("coop_action_flash"):
		return
	var scene_path: String = str(child.scene_file_path)
	if scene_path == "":
		return
	# UI 飘字（伤害数字 / "RELOAD!" / 道具提示）内容动态、各端各自本地生成，不广播；
	# 若广播，接收端克隆不会调 start(text)，会显示场景占位文本 "123456789" 且不消失。
	if scene_path.ends_with("ui/floating_text.tscn"):
		return
	var par := child.get_parent()
	if par == null:
		return
	var grp: String = _layer_group_of(par)
	if grp == "":
		return
	if grp == "PlayerRoot":
		# PlayerRoot 下只处理白名单"持久身体"（走召唤同步）；玩家/镜像等一律忽略
		if PERSISTENT_BODY_SCENES.has(scene_path):
			_register_persistent_body(child, scene_path)
		return
	# 持久身体（drone/vacuum）：走召唤同步（仅视觉镜像 + 变换同步），不做一次性视觉广播
	if PERSISTENT_BODY_SCENES.has(scene_path):
		_register_persistent_body(child, scene_path)
		return
	# 无视觉的持久发射器（shrapnel_bullet/pratt_helmet）：跳过
	if scene_path.ends_with("player_bullet_launcher.tscn"):
		return
	child.set_meta("_coop_visual_broadcast", true)
	var pos := Vector2.ZERO
	var rot := 0.0
	var sc := Vector2.ONE
	if child is Node2D:
		pos = (child as Node2D).global_position
		rot = (child as Node2D).global_rotation
		sc = (child as Node2D).scale
	var method: String = "active_state" if child.has_method("active_state") else ""
	if multiplayer.is_server():
		rpc("_remote_visual_node", scene_path, pos, rot, sc, grp, method)
	else:
		rpc_id(1, "_server_visual_node", scene_path, pos, rot, sc, grp, method)


# 把非 Summoned 的持久身体接入现有召唤同步（仅视觉镜像 + 变换同步）
func _register_persistent_body(child: Node, scene_path: String) -> void:
	if child == null or not is_instance_valid(child):
		return
	if child.has_meta("_coop_body_registered") or child.has_meta("summoned_net_id") or child.has_meta("remote_summoned") or child.has_meta("is_local_summoned"):
		return
	child.set_meta("_coop_body_registered", true)
	print("[etn_coop] persistent-body register scene=%s local=%s" % [scene_path, str(multiplayer.get_unique_id())])
	_on_summoned_spawned(child, scene_path)


@rpc("any_peer", "call_remote", "reliable")
func _server_visual_node(scene_path: String, pos: Vector2, rot: float, sc: Vector2, grp: String, method: String) -> void:
	if not multiplayer.is_server():
		return
	_remote_visual_node(scene_path, pos, rot, sc, grp, method)
	var sender: int = multiplayer.get_remote_sender_id()
	for peer in multiplayer.get_peers():
		if peer != sender:
			rpc_id(peer, "_remote_visual_node", scene_path, pos, rot, sc, grp, method)


@rpc("authority", "call_remote", "reliable")
func _remote_visual_node(scene_path: String, pos: Vector2, rot: float, sc: Vector2, grp: String, method: String) -> void:
	if scene_path == "":
		return
	_visual.spawn_visual_effect(get_tree(), scene_path, pos, rot, sc, grp, method, {})


# ---------------- 玩家同步 ----------------

func _reset_player_sync() -> void:
	battle_active = false
	_state_timer = 0.0
	player_scene_by_peer.clear()
	scene_ready_peers.clear()
	for p in player_by_peer_id.values():
		if p != null and is_instance_valid(p):
			p.queue_free()
	player_by_peer_id.clear()
	player_proxy_by_peer_id.clear()
	player_name_by_peer.clear()
	_reset_enemy_sync()
	_visual.reset()
	_pending_visual.clear()
	_pending_effects.clear()
	_remote_fx_last_ms.clear()
	_remote_flash_last_ms.clear()
	_remote_text_counter = 0
	coin_by_net_id.clear()
	next_coin_net_id = 1
	summoned_by_net_id.clear()
	summoned_proxy_by_net_id.clear()
	summoned_scene_by_net_id.clear()
	summoned_owner_by_net_id.clear()
	pending_local_summons.clear()
	next_summoned_net_id = 1
	_clear_item_visuals()
	_hide_motion_down()
	_visual_roots_hooked.clear()
	down_peer_ids.clear()
	_rescue_target = null
	_rescue_hold = 0.0
	_rescue_prompt_shown = false
	round_upgrade_ready_peers.clear()
	team_game_over_forced = false
	_respawn_token += 1


# 彻底复位一局状态（返回标题/断线/重开时调用），保证同进程内再次开服/进房干净
func _reset_run_state() -> void:
	_reset_player_sync()
	selected_player_scene_by_peer.clear()
	scene_ready_peers.clear()
	_handshaked_peers.clear()
	_pending_hello.clear()
	team_stats.clear()
	_team_stats_timer = 0.0
	chat_log.clear()
	_applying_change = false
	_force_release = false
	_pending_scene_path = ""
	first_round_emitted = false
	_flow_phase = FlowPhase.IDLE
	_select_flow_active = false
	select_ready_by_peer.clear()
	lobby_ready_by_peer.clear()
	_set_select_pause(false)
	_respawn_token += 1
	_diag_pending.clear()
	_latency_samples.clear()
	_delivery_samples.clear()
	_diag_elapsed = 0.0
	_rate_window_msec = 0
	_returning_to_menu_due_to_close = false
	_last_heartbeat_send_msec = 0
	_last_host_packet_msec = 0
	net_extrap_events = 0
	net_hard_snaps = 0
	_enemy_snap_tick = 0
	_enemy_snap_next_tick.clear()
	net_remote_frames = 0
	net_extrap_frames = 0
	net_snapshot_sends = 0
	net_snapshot_entities = 0
	_sim_snapshot_queue.clear()
	_sim_report_timer = 0.0


# 返回标题后延迟关闭连接（先让 return_to_menu/断线包发出，再释放 ENet/端口）
func _close_transport_soon() -> void:
	await get_tree().create_timer(0.3).timeout
	if transport != null or is_lan_game or is_relay:
		close_connection(true)


func _on_first_round_add() -> void:
	if not is_lan_game:
		return
	battle_active = true
	first_round_emitted = true
	if multiplayer.is_server():
		player_scene_by_peer[multiplayer.get_unique_id()] = local_player_scene_path
		rpc("_client_sync_roster", player_scene_by_peer)
		print("[etn_coop] host battle start, roster=%s" % str(player_scene_by_peer))
	else:
		rpc_id(1, "_server_player_ready", local_player_scene_path)
		print("[etn_coop] client battle start, reporting scene=%s" % local_player_scene_path)
	_place_and_refresh_local_player()
	_register_existing_test_room_enemies()
	_hook_visual_roots()
	_report_local_name()
	_schedule_respawn_remotes()


# 场景进入后延迟补生远端镜像：本体 test_room.reset_data → reset_clear_unit 会 queue_free
# PlayerRoot 下不在 "Player" 组的子节点（我们的镜像在 "RemotePlayer"），故需在重置之后再补生。
func _schedule_respawn_remotes() -> void:
	_respawn_token += 1
	var token := _respawn_token
	_respawn_remotes_after(token, 0.3)
	_respawn_remotes_after(token, 0.9)


func _respawn_remotes_after(token: int, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if token != _respawn_token:
		return
	if not is_lan_game or not battle_active:
		return
	_respawn_remote_players()


func _respawn_remote_players() -> void:
	if not is_lan_game or player_scene_by_peer.is_empty():
		return
	var local_id: int = multiplayer.get_unique_id()
	for pid in player_scene_by_peer.keys():
		var peer_id: int = int(pid)
		if peer_id == local_id:
			continue
		var scene_path: String = str(player_scene_by_peer[pid])
		if scene_path == "":
			continue
		spawn_remote_player(peer_id, scene_path)


# 对齐联机版：本地玩家放到房间中心；补发 get_player 让测试场菜单拿到玩家；绑定 PlayerData
func _place_and_refresh_local_player() -> void:
	_placement_token += 1
	var token := _placement_token
	for _i in 15:
		var p := get_local_player()
		if p != null and is_instance_valid(p):
			if not player_scene_by_peer.is_empty():
				p.global_position = _spawn_position_for_peer(multiplayer.get_unique_id())
			PlayerData.player = p
			_ensure_local_proxy(p)
			_attach_name_tag(p, multiplayer.get_unique_id())
			# LAN 下补发 get_player：本体 test_room.reset_data 在本地玩家未生成时会提前 return，
			# 导致 crosshair/UP 面板等拿不到玩家；player_up_screen_date 已做幂等，重复 emit 安全。
			GameEvents.emit_get_player.call_deferred()
			print("[etn_coop] local player placed at %s" % str(p.global_position))
			return
		await get_tree().process_frame
		if token != _placement_token:
			return


func _ensure_local_proxy(player: Node) -> void:
	if player == null or player.has_node("CoopPlayerProxy"):
		return
	# 本地 proxy 仅缓存/meta（setup 本地分支提前返回），不注册进 player_by_peer_id，
	# 避免 _reset_player_sync 误释放本地玩家。
	var proxy: Node = PlayerProxyScript.new()
	proxy.name = "CoopPlayerProxy"
	player.add_child(proxy)
	proxy.setup(multiplayer.get_unique_id(), true)


func _spawn_position_for_peer(peer_id: int) -> Vector2:
	var base := _get_room_center_position()
	var idx: int = player_scene_by_peer.keys().find(peer_id)
	if idx < 0:
		idx = 0
	if idx < SPAWN_OFFSETS.size():
		return base + SPAWN_OFFSETS[idx]
	return base + Vector2.RIGHT.rotated(TAU * float(idx) / 4.0) * SPAWN_RADIUS


# 房间中心：优先 CenterPosition 组；否则在当前场景内按名找 BattleRoom/CenterPosition/SpawnPoint（联机版同款兜底）
func _get_room_center_position() -> Vector2:
	var tree := get_tree()
	if tree == null:
		return Vector2.ZERO
	var marker = tree.get_first_node_in_group("CenterPosition")
	if _usable_marker(marker):
		return (marker as Node2D).global_position
	var scene: Node = tree.current_scene
	if scene != null:
		for wanted in ["BattleRoom", "CenterPosition", "SpawnPoint"]:
			var found := _find_node_named(scene, wanted)
			if _usable_marker(found):
				return (found as Node2D).global_position
	return Vector2.ZERO


func _usable_marker(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not (node is Node2D):
		return false
	return (node as Node2D).is_inside_tree()


func _find_node_named(root: Node, wanted: String) -> Node:
	if root.name == wanted:
		return root
	for child in root.get_children():
		var found := _find_node_named(child, wanted)
		if found != null:
			return found
	return null


func spawn_remote_player(peer_id: int, scene_path: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	if player_by_peer_id.has(peer_id) and is_instance_valid(player_by_peer_id[peer_id]):
		return
	if scene_path == "":
		return
	var root := get_tree().get_first_node_in_group("PlayerRoot")
	if root == null:
		return
	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_warning("[etn_coop] 无法加载玩家场景：%s" % scene_path)
		return
	var p: Node = scene.instantiate()
	p.name = "CoopRemote_%d" % peer_id
	p.set_meta("peer_id", peer_id)
	# 必须先移出 "Player" 组再入树：镜像场景根默认带 groups=["Player"]，若先 add_child，
	# 入树窗口内（镜像 _ready 等）若有代码 get_first_node_in_group("Player")（如 AbilityBox 缓存 player），
	# 会拿到镜像 → 面板随后一直显示镜像的基础属性。
	p.remove_from_group("Player")
	p.add_to_group("RemotePlayer")
	root.add_child(p)
	# 镜像玩家不能污染本机升级道具依赖的全局共享组（如 "Follow"），否则 black_ninpero 等
	# 会遍历到远端 Follow 并把图标重复 add_child 到 PlayerRoot（"already has a parent"）
	for n in p.find_children("*", "", true, false):
		if n.is_in_group("Follow"):
			n.remove_from_group("Follow")
	if p.is_in_group("Follow"):
		p.remove_from_group("Follow")
	p.global_position = _spawn_position_for_peer(peer_id)
	_attach_player_proxy(p, peer_id)
	_attach_name_tag(p, peer_id)
	print("[etn_coop] spawned remote player peer=%d scene=%s" % [peer_id, scene_path])


func _attach_player_proxy(player: Node, peer_id: int) -> void:
	var proxy: Node = PlayerProxyScript.new()
	proxy.name = "CoopPlayerProxy"
	player.add_child(proxy)
	proxy.setup(peer_id, false)
	player_by_peer_id[peer_id] = player
	player_proxy_by_peer_id[peer_id] = proxy


func _get_player_proxy(peer_id: int) -> Node:
	var proxy = player_proxy_by_peer_id.get(peer_id)
	if proxy != null and is_instance_valid(proxy):
		return proxy
	return null


func _physics_process(delta: float) -> void:
	_update_network_diagnostics(delta)
	_network_heartbeat(delta)
	_pump_sim_queue()
	_update_lan_advertise()
	_update_handshake_timeouts()
	if is_lan_game and multiplayer.is_server() and battle_active:
		_team_stats_timer -= delta
		if _team_stats_timer <= 0.0:
			_team_stats_timer = TEAM_STATS_INTERVAL
			_broadcast_team_stats()
	if sim_report_enabled:
		_sim_report_timer += delta
		if _sim_report_timer >= SIM_REPORT_INTERVAL:
			_sim_report_timer = 0.0
			_emit_sim_report()
	if not is_lan_game or not battle_active:
		return
	if multiplayer.multiplayer_peer == null:
		return
	_state_timer -= delta
	if _state_timer <= 0.0:
		_state_timer = STATE_SEND_INTERVAL
		_send_local_player_state()
	if multiplayer.is_server():
		_snapshot_timer -= delta
		if _snapshot_timer <= 0.0:
			_snapshot_timer = ENEMY_SNAPSHOT_INTERVAL
			_send_enemy_snapshot()
	_flush_visuals()
	_update_rescue(delta)


func _send_local_player_state() -> void:
	var p := get_local_player()
	if p == null or p.get("stats") == null:
		return
	var sprite = p.get("sprite_2d")
	var sprite_y: float = sprite.position.y if sprite != null else -17.0
	var state: int = 0
	if absf(sprite_y + 17.0) > 1.0:
		state = 2
	elif p.get("velocity") != null and (p.velocity as Vector2).length() > 5.0:
		state = 1
	var look: Vector2 = p.global_position + Vector2.RIGHT
	if p.get("crosshair_pos") != null and p.crosshair_pos != Vector2.ZERO:
		look = p.crosshair_pos
	var hp: int = int(p.stats.hp)
	var max_hp: int = int(p.stats.max_hp)
	var t_hp: int = int(p.stats.t_hp)
	var max_t_hp: int = int(p.stats.max_t_hp)
	var ammo: int = 0
	if p.stats.get("ammo") != null:
		ammo = int(p.stats.ammo)
	var pos: Vector2 = p.global_position
	var vel: Vector2 = p.velocity if p.get("velocity") != null else Vector2.ZERO
	var cstate: int = 0
	if p.has_method("get_network_character_state"):
		cstate = int(p.call("get_network_character_state"))
	var heading: Vector2 = Vector2.ZERO
	if p.has_method("get_network_heading_direction"):
		var h = p.call("get_network_heading_direction")
		if h is Vector2:
			heading = h
	if multiplayer.is_server():
		rpc("_apply_player_state", multiplayer.get_unique_id(), pos, vel, look, hp, ammo, sprite_y, state, cstate, heading, max_hp, t_hp, max_t_hp)
	else:
		rpc_id(1, "_server_receive_player_state", pos, vel, look, hp, ammo, sprite_y, state, cstate, heading, max_hp, t_hp, max_t_hp)


@rpc("any_peer", "call_remote", "reliable")
func _server_player_ready(scene_path: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	player_scene_by_peer[peer_id] = scene_path
	# 回发完整 roster 给上报者（覆盖它入场前错过的 existing 玩家）
	rpc_id(peer_id, "_client_sync_roster", player_scene_by_peer)
	# 补发入场前已存在的敌人
	_send_existing_enemies_to_peer(peer_id)
	_send_existing_summons_to_peer(peer_id)
	# 告知其它端：有新玩家入场
	for other in multiplayer.get_peers():
		if other != peer_id:
			rpc_id(other, "_spawn_remote_player", peer_id, scene_path)
	spawn_remote_player(peer_id, scene_path)


@rpc("authority", "call_remote", "reliable")
func _spawn_remote_player(peer_id: int, scene_path: String) -> void:
	spawn_remote_player(peer_id, scene_path)


@rpc("authority", "call_remote", "reliable")
func _client_sync_roster(roster: Dictionary) -> void:
	for pid in roster.keys():
		player_scene_by_peer[int(pid)] = str(roster[pid])
		spawn_remote_player(int(pid), str(roster[pid]))


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _server_receive_player_state(
	position: Vector2, velocity: Vector2, look_position: Vector2,
	hp: int, ammo: int, sprite_y: float = -17.0, state: int = 0,
	character_state: int = 0, heading: Vector2 = Vector2.ZERO, max_hp: int = -1,
	t_hp: int = 0, max_t_hp: int = -1
) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	_apply_player_state(peer_id, position, velocity, look_position, hp, ammo, sprite_y, state, character_state, heading, max_hp, t_hp, max_t_hp)
	rpc("_apply_player_state", peer_id, position, velocity, look_position, hp, ammo, sprite_y, state, character_state, heading, max_hp, t_hp, max_t_hp)


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _apply_player_state(
	peer_id: int, position: Vector2, velocity: Vector2, look_position: Vector2,
	hp: int, ammo: int, sprite_y: float = -17.0, state: int = 0,
	character_state: int = 0, heading: Vector2 = Vector2.ZERO, max_hp: int = -1,
	t_hp: int = 0, max_t_hp: int = -1
) -> void:
	# 客户端：收到房主的玩家状态即视为房主存活（战斗期 ~20Hz，比心跳更密）
	if not multiplayer.is_server():
		_last_host_packet_msec = Time.get_ticks_msec()
	var proxy: Node = _get_player_proxy(peer_id)
	if proxy != null and proxy.has_method("apply_state"):
		proxy.apply_state(position, velocity, look_position, hp, ammo, sprite_y, state, character_state, heading, max_hp, t_hp, max_t_hp)


# ---------------- 玩家 ID / 头顶名牌 ----------------

# 单一校验与保存入口：空串允许（回退默认名）；超过 MAX_NAME_LEN 字符则拒绝保存。
func set_local_display_name(value: String) -> bool:
	var clean: String = SettingsScript.sanitize_name(value)
	if clean.length() > SettingsScript.MAX_NAME_LEN:
		return false
	settings.apply_player_id(clean)
	_refresh_name_tag(multiplayer.get_unique_id())
	if is_lan_game and battle_active:
		_report_local_name()
	return true


func get_local_display_name() -> String:
	return str(settings.player_id)


# 加入顺序编号：{1} ∪ get_peers() ∪ {self} 去重升序，index+1（主机=1，依次 2/3/4）。
func _join_index_of(peer_id: int) -> int:
	var ids: Array = [1]
	for pid in multiplayer.get_peers():
		ids.append(int(pid))
	ids.append(multiplayer.get_unique_id())
	var unique: Array = []
	for v in ids:
		if not unique.has(v):
			unique.append(v)
	unique.sort()
	var idx: int = unique.find(peer_id)
	return idx + 1 if idx >= 0 else peer_id


func _default_display_name(peer_id: int) -> String:
	return "Player%d" % _join_index_of(peer_id)


func _display_name_for(peer_id: int) -> String:
	if peer_id == multiplayer.get_unique_id():
		return _local_display_name()
	var custom: String = str(player_name_by_peer.get(peer_id, ""))
	return custom if custom != "" else _default_display_name(peer_id)


func _local_display_name() -> String:
	var custom: String = str(settings.player_id)
	return custom if custom != "" else _default_display_name(multiplayer.get_unique_id())


# ---------------- 聊天室 ----------------
# 发送：本地先回显，再经 host 权威分发（host 直接 rpc，client rpc_id(1)）。
func send_chat(text: String) -> void:
	if not is_lan_game:
		return
	var clean: String = _sanitize_chat(text)
	if clean.is_empty():
		return
	var local_id: int = multiplayer.get_unique_id()
	_append_chat(local_id, _display_name_for(local_id), clean)
	if multiplayer.is_server():
		_fanout_chat(local_id, clean, 0)
	else:
		rpc_id(1, "_server_chat", clean)


# host 分发给所有 client（可排除某个 peer，避免发送者重复收到自己的本地回显）
func _fanout_chat(peer_id: int, text: String, exclude: int) -> void:
	for pid in multiplayer.get_peers():
		if int(pid) != int(exclude):
			rpc_id(int(pid), "_remote_chat", peer_id, text)


func get_chat_log() -> Array:
	return chat_log


func _sanitize_chat(text: String) -> String:
	var clean: String = text.replace("\n", " ").replace("\r", " ").strip_edges()
	if clean.length() > CHAT_TEXT_MAX:
		clean = clean.substr(0, CHAT_TEXT_MAX)
	return clean


func _append_chat(peer_id: int, name: String, text: String) -> void:
	chat_log.append({"peer_id": peer_id, "name": name, "text": text})
	if chat_log.size() > CHAT_LOG_MAX:
		chat_log = chat_log.slice(chat_log.size() - CHAT_LOG_MAX)
	chat_received.emit(peer_id, name, text)


# client -> host：host 用真实发送者 peer id 再广播给所有 client
@rpc("any_peer", "call_remote", "reliable")
func _server_chat(text: String) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	var clean: String = _sanitize_chat(text)
	if clean.is_empty():
		return
	_append_chat(sender, _display_name_for(sender), clean)
	_fanout_chat(sender, clean, sender)


# host -> client
@rpc("authority", "call_remote", "reliable")
func _remote_chat(peer_id: int, text: String) -> void:
	var clean: String = _sanitize_chat(text)
	if clean.is_empty():
		return
	_append_chat(peer_id, _display_name_for(peer_id), clean)


func _report_local_name() -> void:
	var display_name: String = settings.player_id
	if multiplayer.is_server():
		player_name_by_peer[multiplayer.get_unique_id()] = display_name
		rpc("_remote_player_info", multiplayer.get_unique_id(), display_name)
	else:
		rpc_id(1, "_server_player_info", display_name)


func _attach_name_tag(player: Node, peer_id: int) -> void:
	if player == null or not is_instance_valid(player):
		return
	var tag = player.get_node_or_null("CoopNameTag")
	if tag == null:
		tag = NameTagScript.new()
		tag.name = "CoopNameTag"
		player.add_child(tag)
		tag.call("setup", player, _display_name_for(peer_id))
	else:
		tag.call("set_display_text", _display_name_for(peer_id))
	# 仅远端玩家头顶显示生命条 / 倒地 HELP!（本地玩家自身血量见底部 HUD）
	if peer_id != multiplayer.get_unique_id() and tag.has_method("attach_health_bar"):
		tag.call("attach_health_bar", player)


func _refresh_name_tag(peer_id: int) -> void:
	var p: Node = _local_or_remote_player(peer_id)
	if p == null or not is_instance_valid(p):
		return
	var tag = p.get_node_or_null("CoopNameTag")
	if tag != null:
		tag.call("set_display_text", _display_name_for(peer_id))


func _refresh_all_name_tags() -> void:
	_refresh_name_tag(multiplayer.get_unique_id())
	for pid in player_by_peer_id.keys():
		_refresh_name_tag(int(pid))


@rpc("any_peer", "call_remote", "reliable")
func _server_player_info(display_name: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	player_name_by_peer[peer_id] = SettingsScript.sanitize_name(display_name)
	_refresh_name_tag(peer_id)
	rpc_id(peer_id, "_remote_player_info_batch", player_name_by_peer)
	for other in multiplayer.get_peers():
		if other != peer_id:
			rpc_id(other, "_remote_player_info", peer_id, player_name_by_peer[peer_id])


@rpc("authority", "call_remote", "reliable")
func _remote_player_info(peer_id: int, display_name: String) -> void:
	player_name_by_peer[peer_id] = SettingsScript.sanitize_name(display_name)
	_refresh_name_tag(peer_id)


@rpc("authority", "call_remote", "reliable")
func _remote_player_info_batch(names: Dictionary) -> void:
	for pid in names.keys():
		player_name_by_peer[int(pid)] = SettingsScript.sanitize_name(str(names[pid]))
	_refresh_all_name_tags()


# ---------------- 敌人同步 ----------------

func register_enemy_spawn(enemy: Node, scene_path: String) -> void:
	if not is_lan_game or not multiplayer.is_server() or enemy == null:
		return
	if enemy.has_meta("net_id"):
		enemy.remove_meta("net_id")
	var net_id: int = next_enemy_net_id
	next_enemy_net_id += 1
	enemy_by_net_id[net_id] = enemy
	enemy_scene_by_net_id[net_id] = scene_path
	enemy.set_meta("net_id", net_id)
	var max_hp: int = 0
	var hp: int = 0
	var hp_multiplier: float = 1.0
	var damage_multiplier: float = 1.0
	if enemy.get("stats") != null and enemy.stats != null:
		max_hp = int(enemy.stats.max_hp)
		hp = int(enemy.stats.hp)
		hp_multiplier = float(enemy.stats.max_hp_mult)
		damage_multiplier = float(enemy.stats.Enemy_damage_mult)
		_connect_enemy_dead(enemy)
	var comp: Node = _health_component_of(enemy)
	if comp != null and comp.has_signal("damage_taken"):
		var dmg_cb := Callable(self, "_on_server_enemy_damage_taken").bind(enemy)
		if not comp.damage_taken.is_connected(dmg_cb):
			comp.damage_taken.connect(dmg_cb)
	_connect_enemy_parts(enemy, net_id)
	rpc("_spawn_enemy_remote", net_id, scene_path, enemy.global_position, max_hp, hp, hp_multiplier, damage_multiplier, _enemy_part_hps(enemy))


func _attach_enemy_proxy(enemy: Node, net_id: int, server_owned: bool) -> void:
	var existing: Node = enemy.get_node_or_null("CoopEnemyProxy")
	if existing != null:
		enemy_proxy_by_net_id[net_id] = existing
		return
	var proxy: Node = EnemyProxyScript.new()
	proxy.name = "CoopEnemyProxy"
	enemy.add_child(proxy)
	proxy.setup(net_id, server_owned)
	enemy_proxy_by_net_id[net_id] = proxy


# 开发/测试：把当前 EnemiesRoot 下已存在的敌人全部登记（test_room 预置敌人不走生成 hook）。
func register_existing_enemies() -> void:
	if not is_lan_game or not multiplayer.is_server():
		return
	var root := get_tree().get_first_node_in_group("EnemiesRoot")
	if root == null:
		return
	for e in root.get_children():
		if e == null or not is_instance_valid(e) or e.has_meta("net_id"):
			continue
		if e.get("stats") == null:
			continue
		if e.get("is_idle") != null and int(e.is_idle) == 1:
			continue
		register_enemy_spawn(e, str(e.scene_file_path))


# 测试房预置敌人（test_room.tscn 内静态沙包等）不走 spawn_anim，需双方按索引分配相同 net_id 才能同步。
# 仅当当前场景为 test_room；host 权威（连接 is_dead/damage_taken + server proxy），client 挂只读镜像 proxy。
func _register_existing_test_room_enemies() -> void:
	if not is_lan_game or current_scene_path == "":
		return
	if not current_scene_path.contains("test_room"):
		return
	var root := get_tree().get_first_node_in_group("EnemiesRoot")
	if root == null:
		return
	var children: Array = root.get_children()
	for i in children.size():
		var enemy: Node = children[i]
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.has_meta("net_id"):
			continue
		if enemy.get("stats") == null:
			continue
		if enemy.get("is_idle") != null and int(enemy.is_idle) == 1:
			continue
		var net_id: int = TEST_ROOM_NET_BASE + i
		enemy_by_net_id[net_id] = enemy
		enemy_scene_by_net_id[net_id] = str(enemy.scene_file_path)
		enemy.set_meta("net_id", net_id)
		_tag_enemy_parts(enemy, net_id)
		if multiplayer.is_server():
			var comp: Node = _health_component_of(enemy)
			if comp != null and comp.has_signal("damage_taken"):
				var dmg_cb := Callable(self, "_on_server_enemy_damage_taken").bind(enemy)
				if not comp.damage_taken.is_connected(dmg_cb):
					comp.damage_taken.connect(dmg_cb)
			if enemy.get("stats") != null and enemy.stats.has_signal("is_dead"):
				_connect_enemy_dead(enemy)
			_connect_enemy_parts(enemy, net_id)
			_attach_enemy_proxy(enemy, net_id, true)
		else:
			_attach_enemy_proxy(enemy, net_id, false)


func dev_enemy_hp(net_id: int) -> int:
	var enemy = enemy_by_net_id.get(net_id)
	if enemy == null or not is_instance_valid(enemy):
		return -1
	if enemy.get("stats") != null and enemy.stats != null:
		return int(enemy.stats.hp)
	return -1


func dev_preplaced_count() -> int:
	var c: int = 0
	for k in enemy_by_net_id.keys():
		if int(k) >= TEST_ROOM_NET_BASE:
			c += 1
	return c


# 开发/测试：校验本机 "Follow" 组只含本机玩家的 Follow（不含远端镜像的）
func dev_follow_check() -> void:
	var all := get_tree().get_nodes_in_group("Follow")
	var remote: int = 0
	for n in all:
		var par: Node = n.get_parent()
		if n.is_in_group("RemotePlayer") or (par != null and par.is_in_group("RemotePlayer")):
			remote += 1
	print("[etn_coop] dev-follow total=%d remote=%d" % [all.size(), remote])


func dev_preplaced_debug() -> void:
	for k in enemy_by_net_id.keys():
		if int(k) >= TEST_ROOM_NET_BASE:
			var e = enemy_by_net_id[k]
			var valid: bool = e != null and is_instance_valid(e)
			var has_stats: bool = valid and e.get("stats") != null
			print("[etn_coop] dev-preplaced entry id=%d node=%s valid=%s stats=%s" % [int(k), str(e), str(valid), str(has_stats)])


func _preplaced_ids_sorted() -> Array:
	var ids: Array = []
	for k in enemy_by_net_id.keys():
		if int(k) >= TEST_ROOM_NET_BASE:
			ids.append(int(k))
	ids.sort()
	return ids


func dev_preplaced_hp(index: int) -> int:
	var ids: Array = _preplaced_ids_sorted()
	if index < 0 or index >= ids.size():
		return -1
	return dev_enemy_hp(ids[index])


func dev_buff_state(index: int) -> void:
	var ids: Array = _preplaced_ids_sorted()
	if index < 0 or index >= ids.size():
		print("[etn_coop] dev-buff state: no preplaced#%d" % index)
		return
	var enemy = enemy_by_net_id.get(ids[index])
	if enemy == null or not is_instance_valid(enemy):
		print("[etn_coop] dev-buff state: enemy missing")
		return
	var manager = enemy.get("enemy_buff_manager")
	var keys: Array = []
	if manager != null and manager.get("current_buff") != null:
		keys = manager.current_buff.keys()
	var hp: int = int(enemy.stats.hp) if enemy.get("stats") != null else -1
	print("[etn_coop] dev-buff state peer=%s server=%s keys=%s hp=%d" % [str(multiplayer.get_unique_id()), str(multiplayer.is_server()), str(keys), hp])


# 开发/测试：统计本端 GameEvents.enemy_damage_taken 的触发次数（验证归属：客机命中只应客机触发）
var _dev_proc_count: int = 0

func _dev_on_enemy_damage_taken(_a=null, _b=null, _c=null) -> void:
	_dev_proc_count += 1

func dev_proc_state(tag: String) -> void:
	print("[etn_coop] dev-owner %s peer=%s server=%s proc=%d" % [tag, str(multiplayer.get_unique_id()), str(multiplayer.is_server()), _dev_proc_count])


# 开发/测试：对预置敌人 #index 施加 poison_dot buff（客机上会转发 host 权威应用）
func dev_apply_poison(index: int) -> void:
	var ids: Array = _preplaced_ids_sorted()
	if index < 0 or index >= ids.size():
		print("[etn_coop] dev-buff: no preplaced#%d" % index)
		return
	var enemy = enemy_by_net_id.get(ids[index])
	if enemy == null or not is_instance_valid(enemy):
		print("[etn_coop] dev-buff: enemy missing")
		return
	var manager = enemy.get("enemy_buff_manager")
	if manager == null:
		print("[etn_coop] dev-buff: no manager")
		return
	var buff = load("res://resources/buff/enemy_buff/poison_dot.tres")
	if buff == null:
		print("[etn_coop] dev-buff: buff load failed")
		return
	manager.call("apply_buff", buff, [1, 5, 10])
	print("[etn_coop] dev-buff applied poison peer=%s server=%s" % [str(multiplayer.get_unique_id()), str(multiplayer.is_server())])


# 开发/测试：在预置敌人 #index 处生成真实 poison_ring（走 on_damage_dealt → apply_buff 路径）
func dev_spawn_ring(index: int) -> void:
	var ids: Array = _preplaced_ids_sorted()
	if index < 0 or index >= ids.size():
		print("[etn_coop] dev-ring: no preplaced#%d" % index)
		return
	var enemy = enemy_by_net_id.get(ids[index])
	if enemy == null or not is_instance_valid(enemy):
		print("[etn_coop] dev-ring: enemy missing")
		return
	var layer := get_tree().get_first_node_in_group("SELayer")
	if layer == null:
		print("[etn_coop] dev-ring: no SELayer")
		return
	var scene := load("res://scenes/bullet/poison_ring.tscn") as PackedScene
	if scene == null:
		print("[etn_coop] dev-ring: scene load failed")
		return
	var ring: Node = scene.instantiate()
	layer.add_child(ring)
	var hb = ring.get("hit_box")
	if hb != null:
		hb.damage_data = DamageData.fill(null, {"damage": 5, "type": GameTags.POISON_DAMAGE, "source": GameTags.EQUIP, "node": ring})
	ring.global_position = enemy.global_position
	ring.call("active_state")
	print("[etn_coop] dev-ring spawned at preplaced#%d peer=%s server=%s" % [index, str(multiplayer.get_unique_id()), str(multiplayer.is_server())])


# 开发/测试：host 生成一个真实敌人（触发 on_enemy_spawned → _spawn_enemy_remote 到客机）
func dev_spawn_real_enemy(scene_path: String = "res://scenes/enemies/sweeper.tscn") -> void:
	if not is_lan_game or not multiplayer.is_server():
		return
	var scene := load(scene_path) as PackedScene
	if scene == null:
		print("[etn_coop] dev-spawn-enemy missing: %s" % scene_path)
		return
	var root := get_tree().get_first_node_in_group("EnemiesRoot")
	if root == null:
		return
	var e: Node = scene.instantiate()
	root.add_child(e)
	var p := get_local_player()
	var spawn_pos: Vector2 = Vector2.ZERO
	if p != null:
		spawn_pos = p.global_position + Vector2(220, 0)
	# 若存在远端镜像，生成在镜像旁（便于验证 host 选敌纳入远端玩家）
	for k in player_by_peer_id.keys():
		var m = player_by_peer_id[k]
		if m != null and is_instance_valid(m):
			spawn_pos = m.global_position + Vector2(60, 0)
			break
	e.global_position = spawn_pos
	if e.has_method("active_state"):
		e.active_state()
	_on_enemy_spawned(e, scene_path)
	print("[etn_coop] dev-spawn-enemy %s net=%s" % [scene_path.get_file(), str(e.get_meta("net_id", -1))])


# 开发/测试：对敌人施加策反（客户机调用会转发 host）。net_id<0 时取最小 net_id（通常是非预置真实敌人）
func dev_convert_enemy(net_id: int = -1, power: int = 1000) -> void:
	if net_id < 0:
		var best: int = 1 << 30
		for k in enemy_by_net_id.keys():
			best = mini(best, int(k))
		net_id = best if best != (1 << 30) else -1
	if net_id < 0:
		return
	var e = enemy_by_net_id.get(net_id)
	if e == null or not is_instance_valid(e) or not e.has_method("apply_conversion_power"):
		return
	e.call("apply_conversion_power", power)
	var conv: bool = bool(e.call("is_converted")) if e.has_method("is_converted") else false
	var gauge: int = int(e.get("convert_gauge")) if e.get("convert_gauge") != null else -1
	print("[etn_coop] dev-convert local=%s net=%d power=%d converted=%s gauge=%d" % [str(multiplayer.get_unique_id()), net_id, power, str(conv), gauge])


func dev_enemy_converted_state(net_id: int = -1) -> void:
	if net_id < 0:
		var best: int = 1 << 30
		for k in enemy_by_net_id.keys():
			best = mini(best, int(k))
		net_id = best if best != (1 << 30) else -1
	if net_id < 0:
		return
	var e = enemy_by_net_id.get(net_id)
	if e == null or not is_instance_valid(e):
		print("[etn_coop] dev-conv-state local=%s net=%d missing" % [str(multiplayer.get_unique_id()), net_id])
		return
	var conv: bool = bool(e.call("is_converted")) if e.has_method("is_converted") else false
	var gauge: int = int(e.get("convert_gauge")) if e.get("convert_gauge") != null else -1
	print("[etn_coop] dev-conv-state local=%s net=%d converted=%s gauge=%d" % [str(multiplayer.get_unique_id()), net_id, str(conv), gauge])


# 开发/测试：打印各敌人的 get_target（验证 host 是否锁定远端镜像）
func dev_enemy_targets() -> void:
	for net_id in enemy_by_net_id.keys():
		var e = enemy_by_net_id[net_id]
		if e == null or not is_instance_valid(e) or not e.has_method("get_target"):
			continue
		var t = e.call("get_target")
		var tname := "null"
		if t != null and is_instance_valid(t):
			tname = str(t.name) + ("[RemotePlayer]" if t.is_in_group("RemotePlayer") else "")
		print("[etn_coop] enemy net=%d target=%s" % [net_id, tname])


# 开发/测试：本机获取一件升级（触发本体 upgrade_manager.apply_upgrade → 生成道具 + 发 ability_upgrade_added）
func dev_grant_item(item_id: String) -> void:
	if not is_lan_game:
		return
	var res = load("res://resources/upgrades/%s.tres" % item_id)
	if res == null:
		print("[etn_coop] dev-grant missing upgrade: %s" % item_id)
		return
	GameEvents.emit_add_player_upgrade(res)
	print("[etn_coop] dev-grant item=%s local=%s" % [item_id, str(multiplayer.get_unique_id())])


# 开发/测试：host 对预置敌人 #index 施加伤害（走自然路径 → 广播命中反馈 + 快照 hp 同步）。
func dev_damage_preplaced(index: int, amount: int) -> void:
	var ids: Array = _preplaced_ids_sorted()
	if index < 0 or index >= ids.size():
		print("[etn_coop] dev preplaced#%d missing" % index)
		return
	var net_id: int = int(ids[index])
	var enemy = enemy_by_net_id.get(net_id)
	if enemy == null or not is_instance_valid(enemy):
		print("[etn_coop] dev preplaced#%d missing" % index)
		return
	var comp: Node = _health_component_of(enemy)
	if comp == null:
		print("[etn_coop] dev preplaced#%d no component" % index)
		return
	var data: DamageData = DamageData.make({
		"damage": amount,
		"type": GameTags.BULLET_DAMAGE,
		"source": DamageRouter.source_tag(Faction.PLAYER_SIDE),
		"node": get_local_player(),
	})
	comp.take_damage(data)
	var proxy = enemy_proxy_by_net_id.get(net_id)
	var pending: int = int(proxy.get("pending_damage")) if proxy != null and is_instance_valid(proxy) else -1
	print("[etn_coop] dev preplaced#%d (net_id=%d) local hp=%d predicted=%s pending=%d server=%s" % [index, net_id, int(enemy.stats.hp), str(enemy.get_meta("predicted_hp", -1)), pending, str(multiplayer.is_server())])


# 开发/测试：客户端对指定 net_id 敌人发起一次伤害（走拦截器 → 请求服务端权威）。
func dev_hit_enemy(net_id: int, amount: int) -> void:
	if not is_lan_game or multiplayer.is_server():
		return
	var enemy = enemy_by_net_id.get(net_id)
	if enemy == null or not is_instance_valid(enemy):
		return
	var comp: Node = _health_component_of(enemy)
	if comp == null:
		return
	var d := DamageData.new()
	d.base_damage = amount
	d.damage_type.append(GameTags.BULLET_DAMAGE)
	d.source_type.append(GameTags.PLAYER)
	comp.take_damage(d)
	var proxy = enemy_proxy_by_net_id.get(net_id)
	var pending: int = int(proxy.get("pending_damage")) if proxy != null and is_instance_valid(proxy) else -1
	print("[etn_coop] dev-hit net_id=%d predicted_hp=%s pending=%d hp=%d" % [
		net_id, str(enemy.get_meta("predicted_hp", -1)), pending, int(enemy.stats.hp)
	])


# 开发/测试：host 生成带 body_part 的敌人，返回 net_id
func dev_spawn_part_enemy(scene_path: String = "res://scenes/enemies/tester_automaton_shield.tscn") -> int:
	if not is_lan_game or not multiplayer.is_server():
		return -1
	var scene := load(scene_path) as PackedScene
	if scene == null:
		print("[etn_coop] dev-part-enemy missing: %s" % scene_path)
		return -1
	var root := get_tree().get_first_node_in_group("EnemiesRoot")
	if root == null:
		return -1
	var e: Node = scene.instantiate()
	root.add_child(e)
	var p := get_local_player()
	if p != null:
		e.global_position = p.global_position + Vector2(220, 0)
	if e.has_method("active_state"):
		e.call("active_state")
	_on_enemy_spawned(e, scene_path)
	var net_id: int = int(e.get_meta("net_id", -1))
	print("[etn_coop] dev-part-enemy %s net=%d part_hp=%s" % [scene_path.get_file(), net_id, str(_enemy_part_hps(e))])
	return net_id


# 开发/测试：读取敌人指定部件当前 hp（-1 = 无该部件）
func dev_enemy_part_hp(net_id: int, part_index: int) -> int:
	var e = enemy_by_net_id.get(net_id)
	if e == null or not is_instance_valid(e):
		return -1
	var parts = e.get("body_part")
	if parts == null or not (parts is Array) or part_index < 0 or part_index >= parts.size():
		return -1
	var part = parts[part_index]
	if part == null or not is_instance_valid(part) or part.get("stats") == null:
		return -1
	return int(part.stats.hp)


# 开发/测试：读取最小 net_id（通常是非预置的真实敌人）
func dev_first_enemy_net_id() -> int:
	var best: int = 1 << 30
	for k in enemy_by_net_id.keys():
		best = mini(best, int(k))
	return best if best != (1 << 30) else -1


# 开发/测试：对敌人部件施加伤害（走真实 take_damage → 客机拦截预测 + 转发 host 权威）
func dev_hit_enemy_part(net_id: int, part_index: int, amount: int) -> void:
	var e = enemy_by_net_id.get(net_id)
	if e == null or not is_instance_valid(e):
		print("[etn_coop] dev-part-hit net=%d missing" % net_id)
		return
	var parts = e.get("body_part")
	if parts == null or not (parts is Array) or part_index < 0 or part_index >= parts.size():
		print("[etn_coop] dev-part-hit net=%d bad_part=%d" % [net_id, part_index])
		return
	var part = parts[part_index]
	var comp: Node = _health_component_of(part)
	if comp == null or not comp.has_method("take_damage"):
		print("[etn_coop] dev-part-hit net=%d no_component" % net_id)
		return
	var d := DamageData.new()
	d.base_damage = amount
	d.damage_type.append(GameTags.BULLET_DAMAGE)
	d.source_type.append(GameTags.PLAYER)
	comp.take_damage(d)
	print("[etn_coop] dev-part-hit local=%s net=%d part=%d hp=%s predicted_hp=%s" % [
		str(multiplayer.get_unique_id()), net_id, part_index,
		str(dev_enemy_part_hp(net_id, part_index)), str(part.get_meta("predicted_hp", -1))
	])


# 开发/测试：host 重新向所有已连接 peer 补发"已存在敌人"（走 _send_existing_enemies_to_peer，含 part_hps）
func dev_resend_existing() -> void:
	if not multiplayer.is_server():
		return
	for id in multiplayer.get_peers():
		_send_existing_enemies_to_peer(int(id))
	print("[etn_coop] dev-resend existing to peers=%d enemies=%d" % [multiplayer.get_peers().size(), enemy_by_net_id.size()])


# 开发/测试：客机侧移除某敌人镜像（供验证补发路径，避免 _spawn_enemy_remote 因已存在而跳过）
func dev_evict_enemy(net_id: int) -> void:
	var e = enemy_by_net_id.get(net_id)
	if e != null and is_instance_valid(e):
		e.queue_free()
	enemy_by_net_id.erase(net_id)
	enemy_scene_by_net_id.erase(net_id)
	enemy_proxy_by_net_id.erase(net_id)
	print("[etn_coop] dev-evict net=%d remaining=%d" % [net_id, enemy_by_net_id.size()])


# 开发/测试：打印本端召唤炮台 %Sprite2D 各子 sprite scale（验证后坐不再累积放大）
func dev_turret_scale() -> String:
	var t := get_tree()
	if t == null:
		return "(no tree)"
	var lines: Array = []
	for s in t.get_nodes_in_group("Summoned"):
		if s == null or not is_instance_valid(s) or not s.has_method("network_play_action"):
			continue
		var turret = s.get_node_or_null("%Sprite2D")
		if turret == null:
			continue
		var scales: Array = []
		for child in turret.get_children():
			scales.append("%.3f,%.3f" % [child.scale.x, child.scale.y])
		var wait_time: float = -1.0
		var st = s.get_node_or_null("ShootTimer")
		if st != null:
			wait_time = st.wait_time
		lines.append("net=%s owner=%d wait=%.3f n=%d scales=[%s]" % [
			str(s.get_meta("summoned_net_id", -1)), int(s.get_meta("owner_peer_id", -1)),
			wait_time, turret.get_child_count(), ", ".join(scales)
		])
	return "\n".join(lines) if lines.size() > 0 else "(no turret)"


# 开发/测试：打印远端镜像的 follow 图标链（每个图标的 follow_mark 路径；应链式而非全指向镜像玩家）
func dev_follow_marks() -> String:
	var lines: Array = []
	for peer_id in item_visual_by_peer.keys():
		var arr = item_visual_by_peer[peer_id]
		if arr == null:
			continue
		for icon in arr:
			if icon == null or not is_instance_valid(icon) or not icon.has_method("get_follow"):
				continue
			var mark = icon.get("follow_mark")
			var mpath: String = "(null)"
			if mark != null and is_instance_valid(mark):
				mpath = str(mark.get_path())
			lines.append("peer=%d icon=%s mark=%s" % [int(peer_id), str(icon.name), mpath])
	return "\n".join(lines) if lines.size() > 0 else "(no follow icons)"


# dev：打印玩家 ID / 名牌状态（本地与各远端镜像）。
func dev_name_state() -> String:
	var parts: Array[String] = []
	parts.append("local_name='%s'" % _local_display_name())
	parts.append("table=%s" % str(player_name_by_peer))
	var local: Node = get_local_player()
	if local != null:
		parts.append(_dev_tag_desc("local", local))
	for pid in player_by_peer_id.keys():
		var m = player_by_peer_id[pid]
		if m != null and is_instance_valid(m):
			parts.append(_dev_tag_desc("peer=%d" % int(pid), m))
	return " | ".join(parts)


func _dev_tag_desc(tag: String, player: Node) -> String:
	var node = player.get_node_or_null("CoopNameTag")
	if node == null:
		return "%s tag=<none>" % tag
	var spr = player.get("sprite_2d")
	var spr_y: float = spr.position.y if spr != null else 0.0
	return "%s text='%s' tag_y=%.1f spr_y=%.1f" % [tag, str(node.get("text")), node.position.y, spr_y]


# 自测：打印本地 + 各远端玩家的 hp/max_hp/t_hp/max_t_hp/倒地/HELP! 可见性。
func dev_health_state() -> String:
	var parts: Array = []
	var local: Node = get_local_player()
	if local != null:
		parts.append(_dev_health_desc("local", local))
	for pid in player_by_peer_id.keys():
		var m = player_by_peer_id[pid]
		if m != null and is_instance_valid(m):
			parts.append(_dev_health_desc("peer=%d" % int(pid), m))
	return " | ".join(parts)


func _dev_health_desc(tag: String, player: Node) -> String:
	var stats = player.get("stats")
	var hp: int = int(stats.hp) if stats != null else -1
	var max_hp: int = int(stats.max_hp) if stats != null else -1
	var t_hp: int = int(stats.t_hp) if stats != null else -1
	var max_t_hp: int = int(stats.max_t_hp) if stats != null else -1
	var downed: bool = player.get("is_downed") == true
	var help_visible: bool = false
	var nt = player.get_node_or_null("CoopNameTag")
	if nt != null:
		var h = nt.get_node_or_null("HelpTag")
		if h is CanvasItem:
			help_visible = (h as CanvasItem).visible
	return "%s hp=%d/%d t=%d/%d downed=%s help=%s" % [tag, hp, max_hp, t_hp, max_t_hp, str(downed), str(help_visible)]


# 连接 is_dead（ONE_SHOT）。复活后（沙包 spawn_hp 会 dead_lock=false）需重连。
func _connect_enemy_dead(enemy: Node) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.get("stats") == null or not enemy.stats.has_signal("is_dead"):
		return
	var dead_cb := Callable(self, "_on_server_enemy_dead").bind(enemy)
	if not enemy.stats.is_dead.is_connected(dead_cb):
		enemy.stats.is_dead.connect(dead_cb, CONNECT_ONE_SHOT)


func _on_server_enemy_dead(enemy: Node) -> void:
	if not multiplayer.is_server():
		return
	if enemy == null or not is_instance_valid(enemy) or not enemy.has_meta("net_id"):
		return
	var net_id: int = int(enemy.get_meta("net_id"))
	if enemy_by_net_id.get(net_id) != enemy:
		return
	var icon: String = ""
	var pos: Vector2 = Vector2.ZERO
	if enemy.get("icon") != null:
		icon = str(enemy.icon)
	pos = enemy.global_position
	rpc("_play_enemy_death_remote", net_id, icon, pos)
	# 本体部分敌人（测试房沙包）on_dead 为 call_deferred 且会 spawn_hp 回满血；
	# 延迟一帧判定：hp>0 = 复活（保留 net_id + 重连 is_dead）；否则真死（despawn）。
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(enemy) and enemy.get("stats") != null and int(enemy.stats.hp) > 0:
		_connect_enemy_dead(enemy)
		return
	enemy_by_net_id.erase(net_id)
	enemy_scene_by_net_id.erase(net_id)
	enemy_proxy_by_net_id.erase(net_id)
	_add_team_kill(int(last_attacker_by_net_id.get(net_id, multiplayer.get_unique_id())))
	last_attacker_by_net_id.erase(net_id)
	rpc("_despawn_enemy_remote", net_id)


@rpc("authority", "call_remote", "reliable")
func _play_enemy_death_remote(net_id: int, icon: String, position: Vector2) -> void:
	if multiplayer.is_server():
		return
	var enemy = enemy_by_net_id.get(net_id)
	if enemy != null and is_instance_valid(enemy) and enemy.has_method("play_network_death"):
		return
	_play_enemy_death(icon, position)


func _play_enemy_death(icon: String, position: Vector2) -> void:
	if icon == "":
		return
	var root := get_tree().get_first_node_in_group("EnemiesRoot")
	if root == null:
		return
	var ins = DEATH_GPU.instantiate()
	if ins == null:
		return
	root.add_child(ins)
	if ins is Node2D:
		(ins as Node2D).global_position = position + Vector2.UP * 15.0
	var gp = ins.get("gpu_particles_2d")
	if gp != null:
		var tex = load("res://sprites/enemies/%s.png" % icon)
		if tex != null:
			gp.texture = tex
	var ap = ins.get("animation_player")
	if ap != null and ap.has_method("play"):
		ap.call("play", "death")
	SoundManager.play_sfx("DeadSounds")


func _send_enemy_snapshot() -> void:
	if multiplayer.get_peers().is_empty():
		return
	var now: int = Time.get_ticks_msec()
	_enemy_snap_tick += 1
	var tick: int = _enemy_snap_tick
	var ids_and_hp := PackedInt32Array()
	var positions_and_velocities := PackedVector2Array()
	var states := PackedInt32Array()
	var conv_flags := PackedInt32Array()
	var gauges := PackedInt32Array()
	var seen: Dictionary = {}
	for net_id in enemy_by_net_id.keys():
		var enemy = enemy_by_net_id[net_id]
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.get("is_idle") != null and int(enemy.is_idle) == 1:
			continue
		var hp: int = 0
		if enemy.get("stats") != null and enemy.stats != null:
			hp = int(enemy.stats.hp)
		var pos: Vector2 = enemy.global_position
		var vel: Vector2 = enemy.velocity if enemy.get("velocity") != null else Vector2.ZERO
		_record_enemy_pos(net_id, now, pos)
		var st: int = -1
		var sm = enemy.get("state_machine")
		if sm != null and is_instance_valid(sm):
			st = int(sm.get("current_state"))
		var conv: int = 0
		if enemy.has_method("is_converted") and bool(enemy.call("is_converted")):
			conv = 1
		var gauge: int = int(enemy.get("convert_gauge")) if enemy.get("convert_gauge") != null else 0
		seen[net_id] = true
		var prev = _enemy_snap_cache.get(net_id)
		# 优先级分频：远/静置敌人降频；hp 变化（受伤/死亡）立即发
		var hp_changed: bool = prev == null or hp != int(prev["h"])
		if not hp_changed and tick < int(_enemy_snap_next_tick.get(net_id, 0)):
			continue
		# 变化检测：位置/速度 epsilon + hp + 状态 + 策反态/gauge；600ms 心跳强制刷新
		if prev != null:
			var dt: int = now - int(prev["t"])
			var dp: float = (pos - (prev["p"] as Vector2)).length_squared()
			var dv: float = (vel - (prev["v"] as Vector2)).length_squared()
			if dt < ENEMY_SNAPSHOT_HEARTBEAT_MSEC and dp <= ENEMY_SNAPSHOT_POS_EPS2 and dv <= ENEMY_SNAPSHOT_VEL_EPS2 and hp == int(prev["h"]) and st == int(prev.get("s", -1)) and conv == int(prev.get("c", 0)) and gauge == int(prev.get("g", 0)):
				continue
		ids_and_hp.append(int(net_id))
		ids_and_hp.append(hp)
		positions_and_velocities.append(pos)
		positions_and_velocities.append(vel)
		states.append(st)
		conv_flags.append(conv)
		gauges.append(gauge)
		_enemy_snap_cache[net_id] = {"p": pos, "v": vel, "h": hp, "s": st, "c": conv, "g": gauge, "t": now}
		_enemy_snap_next_tick[net_id] = tick + _snapshot_cadence_mult(enemy)
	for k in _enemy_snap_cache.keys():
		if not seen.has(k):
			_enemy_snap_cache.erase(k)
			_enemy_snap_next_tick.erase(k)
	var total: int = ids_and_hp.size() / 2
	var i: int = 0
	var limit: int = maxi(1, enemy_snapshot_batch_limit)
	while i < total:
		var n: int = mini(limit, total - i)
		rpc(
			"_enemy_snapshot",
			ids_and_hp.slice(i * 2, (i + n) * 2),
			positions_and_velocities.slice(i * 2, (i + n) * 2),
			states.slice(i, i + n),
			conv_flags.slice(i, i + n),
			gauges.slice(i, i + n)
		)
		net_snapshot_sends += 1
		net_snapshot_entities += n
		i += n


# 分频倍率：距最近玩家越近越发（1=每 tick，2/3=降频）
func _snapshot_cadence_mult(enemy: Node) -> int:
	var nearest: float = INF
	var p := get_local_player()
	if p is Node2D:
		nearest = (p as Node2D).global_position.distance_to(enemy.global_position)
	for pid in player_by_peer_id.keys():
		var m = player_by_peer_id[pid]
		if m != null and is_instance_valid(m) and m is Node2D:
			nearest = minf(nearest, (m as Node2D).global_position.distance_to(enemy.global_position))
	if nearest <= ENEMY_SNAP_NEAR_DIST:
		return 1
	if nearest <= ENEMY_SNAP_MID_DIST:
		return 2
	return 3


func _send_existing_enemies_to_peer(peer_id: int) -> void:
	for net_id in enemy_by_net_id.keys():
		var enemy = enemy_by_net_id[net_id]
		if enemy == null or not is_instance_valid(enemy):
			continue
		if not enemy_scene_by_net_id.has(net_id):
			continue
		if enemy.get("is_idle") != null and int(enemy.is_idle) == 1:
			continue
		var max_hp: int = 0
		var hp: int = 0
		var hp_multiplier: float = 1.0
		var damage_multiplier: float = 1.0
		if enemy.get("stats") != null and enemy.stats != null:
			max_hp = int(enemy.stats.max_hp)
			hp = int(enemy.stats.hp)
			hp_multiplier = float(enemy.stats.max_hp_mult)
			damage_multiplier = float(enemy.stats.Enemy_damage_mult)
		rpc_id(peer_id, "_spawn_enemy_remote", int(net_id), str(enemy_scene_by_net_id[net_id]), enemy.global_position, max_hp, hp, hp_multiplier, damage_multiplier, _enemy_part_hps(enemy))


func _reset_enemy_sync() -> void:
	enemy_by_net_id.clear()
	enemy_scene_by_net_id.clear()
	enemy_proxy_by_net_id.clear()
	next_enemy_net_id = 1
	_snapshot_timer = 0.0
	_enemy_snap_cache.clear()
	last_attacker_by_net_id.clear()
	_enemy_pos_history.clear()
	net_hits_accepted = 0
	net_hits_rejected = 0


func _damage_to_dict(d: DamageData) -> Dictionary:
	return {
		"damage": d.base_damage,
		"crit": d.is_crit,
		"knockback": d.knockback_force,
		"direction": d.knockback_direction,
		"type": d.damage_type.duplicate(),
		"source": d.source_type.duplicate(),
		"flags": d.flags.duplicate(),
		"convert": d.convert_power,
		"center": d.hit_box_center,
		"owner_peer": d.owner_peer,
		"source_node": str(d.source_node),
	}


# 优先取"自身直属子级 HealthComponent"（根敌人/部件各自的组件），避免多部件敌人误取到部件组件；
# 直属子级不存在时再递归（兼容组件嵌在子节点的场景）
func _health_component_of(node: Node) -> Node:
	if node == null:
		return null
	if node is HealthComponent:
		return node
	for child in node.get_children():
		if child is HealthComponent:
			return child
	for child in node.get_children():
		var found: Node = _health_component_of(child)
		if found != null:
			return found
	return null


@rpc("authority", "call_remote", "reliable")
func _spawn_enemy_remote(
	net_id: int, scene_path: String, position: Vector2,
	max_hp: int = 0, hp: int = 0, hp_multiplier: float = 1.0, damage_multiplier: float = 1.0,
	part_hps: PackedInt32Array = PackedInt32Array()
) -> void:
	if multiplayer.is_server() or enemy_by_net_id.has(net_id):
		return
	var root := get_tree().get_first_node_in_group("EnemiesRoot")
	var scene := load(scene_path) as PackedScene
	if root == null or scene == null:
		return
	var enemy: Node = scene.instantiate()
	root.add_child(enemy)
	enemy.global_position = position
	_attach_enemy_proxy(enemy, net_id, false)
	if enemy.get("stats") != null and enemy.stats != null:
		enemy.stats.max_hp_mult = hp_multiplier
		enemy.stats.Enemy_damage_mult = damage_multiplier
		enemy.stats.Enemy_bullet_damage_mult = damage_multiplier
		enemy.stats.update_body_ability()
		if max_hp > 0:
			enemy.stats.max_hp = max_hp
			enemy.stats.hp = max(1, hp)
	if enemy.has_method("active_state"):
		enemy.active_state()
	# active_state 会重开 root 物理 + StateMachine，镜像须再次停 AI（否则本地跑 AI/开火）
	var eproxy = enemy_proxy_by_net_id.get(net_id)
	if eproxy != null and is_instance_valid(eproxy) and eproxy.has_method("disable_mirror_ai"):
		eproxy.call("disable_mirror_ai")
	# 多部件敌人：本体 spawn_anim 会逐个 active_state 部件，镜像补上（仅视觉）
	var parts = enemy.get("body_part")
	if parts is Array:
		for i in parts.size():
			var part = parts[i]
			if part != null and is_instance_valid(part) and part.has_method("active_state"):
				part.call("active_state")
			if part != null and is_instance_valid(part):
				part.set_meta("coop_owner_net_id", net_id)
				part.set_meta("coop_part_index", i)
				if i < part_hps.size() and part_hps[i] >= 0 and part.get("stats") != null:
					part.stats.hp = part_hps[i]
	if enemy.get("stats") != null and enemy.stats != null and max_hp > 0:
		enemy.stats.max_hp = max_hp
		enemy.stats.hp = max(1, hp)
	enemy_by_net_id[net_id] = enemy
	enemy_scene_by_net_id[net_id] = scene_path
	_play_remote_enemy_spawn_anim(position)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _enemy_snapshot(ids_and_hp: PackedInt32Array, positions_and_velocities: PackedVector2Array, states: PackedInt32Array, conv_flags: PackedInt32Array, gauges: PackedInt32Array) -> void:
	if multiplayer.is_server():
		return
	# 压测模拟：丢包 + 延迟/抖动（延迟投递队列）
	if sim_loss_pct > 0.0 and randf() * 100.0 < sim_loss_pct:
		return
	if sim_latency_ms > 0.0 or sim_jitter_ms > 0.0:
		var rel: int = Time.get_ticks_msec() + maxi(0, int(sim_latency_ms + randf_range(-sim_jitter_ms, sim_jitter_ms)))
		_sim_snapshot_queue.append({"rel": rel, "p": [ids_and_hp, positions_and_velocities, states, conv_flags, gauges]})
		return
	_apply_enemy_snapshot(ids_and_hp, positions_and_velocities, states, conv_flags, gauges)


func _apply_enemy_snapshot(ids_and_hp: PackedInt32Array, positions_and_velocities: PackedVector2Array, states: PackedInt32Array, conv_flags: PackedInt32Array, gauges: PackedInt32Array) -> void:
	var count: int = mini(ids_and_hp.size() / 2, positions_and_velocities.size() / 2)
	for i in count:
		var net_id: int = ids_and_hp[i * 2]
		if not enemy_by_net_id.has(net_id):
			continue
		var enemy = enemy_by_net_id[net_id]
		if enemy == null or not is_instance_valid(enemy):
			enemy_by_net_id.erase(net_id)
			enemy_scene_by_net_id.erase(net_id)
			enemy_proxy_by_net_id.erase(net_id)
			continue
		var proxy = enemy_proxy_by_net_id.get(net_id)
		if proxy != null and proxy.has_method("apply_snapshot"):
			var st: int = states[i] if i < states.size() else -1
			var conv: bool = (conv_flags[i] != 0) if i < conv_flags.size() else false
			var gauge: int = gauges[i] if i < gauges.size() else 0
			proxy.apply_snapshot(positions_and_velocities[i * 2], positions_and_velocities[i * 2 + 1], ids_and_hp[i * 2 + 1], st, conv, gauge)


# 释放到期的模拟延迟快照
func _pump_sim_queue() -> void:
	if _sim_snapshot_queue.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	while not _sim_snapshot_queue.is_empty() and int(_sim_snapshot_queue[0]["rel"]) <= now:
		var e: Dictionary = _sim_snapshot_queue.pop_front()
		var p: Array = e["p"]
		_apply_enemy_snapshot(p[0], p[1], p[2], p[3], p[4])


# 压测指标上报（每 SIM_REPORT_INTERVAL 一次）；格式稳定，供回归脚本解析
func _emit_sim_report() -> void:
	var role: String = "host" if multiplayer.is_server() else "client"
	var extrap_rate: float = 0.0
	if net_remote_frames > 0:
		extrap_rate = 100.0 * float(net_extrap_frames) / float(net_remote_frames)
	print("[etn_coop] sim-report role=%s lat=%.0f jit=%.0f loss=%.0f rtt=%.0f jitter=%.0f extrap_rate=%.1f hard_snaps=%d extrap_events=%d snap_sends=%d snap_entities=%d remote_frames=%d bullet_tx=%.1f bullet_rx=%.1f effect_tx=%.1f effect_rx=%.1f" % [
		role, sim_latency_ms, sim_jitter_ms, sim_loss_pct, net_rtt_ms, net_jitter_ms,
		extrap_rate, net_hard_snaps, net_extrap_events, net_snapshot_sends, net_snapshot_entities, net_remote_frames,
		_rate_bullet_sent, _rate_bullet_recv, _rate_effect_sent, _rate_effect_recv])


@rpc("authority", "call_remote", "reliable")
func _despawn_enemy_remote(net_id: int) -> void:
	if multiplayer.is_server():
		return
	var enemy = enemy_by_net_id.get(net_id)
	if enemy != null and is_instance_valid(enemy):
		enemy.queue_free()
	enemy_by_net_id.erase(net_id)
	enemy_scene_by_net_id.erase(net_id)
	enemy_proxy_by_net_id.erase(net_id)


@rpc("any_peer", "call_remote", "reliable")
func _server_enemy_hit(net_id: int, cfg: Dictionary, victim_pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var enemy = enemy_by_net_id.get(net_id)
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.get("is_idle") != null and int(enemy.is_idle) == 1:
		return
	var component: Node = _health_component_of(enemy)
	if component == null or not component.has_method("take_damage"):
		return
	var attacker: int = multiplayer.get_remote_sender_id()
	# 轻量合理性校验（保持客户端权威，仅拦明显异常：尸体/超距/回滚位置不符）
	if not _validate_enemy_hit(enemy, attacker, victim_pos):
		net_hits_rejected += 1
		return
	net_hits_accepted += 1
	var data: DamageData = DamageData.fill(null, cfg)
	data.owner_peer = attacker
	last_attacker_by_net_id[net_id] = attacker
	# 抑制本体自然表现（飘字/闪白），由 mod 按来源频率统一回放（host 侧客机命中 = 远程来源）
	var hp_before: int = int(enemy.stats.hp) if enemy.get("stats") != null else 0
	component.take_damage(data, true, true)
	var hp_after: int = int(enemy.stats.hp) if enemy.get("stats") != null else 0
	var actual: int = maxi(0, hp_before - hp_after)
	if actual > 0:
		_add_team_damage(attacker, actual)
		var killed: bool = hp_before > 0 and hp_after <= 0
		_replay_hit_feedback(enemy, data, actual, true)
		rpc("_remote_hit_feedback", net_id, actual, cfg, attacker, true)
		if attacker != multiplayer.get_unique_id():
			# 归属端在本机发射 enemy_damage_taken(_dead) 触发其道具/PS（host 端已被 suppress_proc 抑制）
			rpc_id(attacker, "_remote_enemy_proc", net_id, actual, _damage_to_dict(data), killed)


# host 记录敌人位置历史（供命中回滚合理性校验）
func _record_enemy_pos(net_id: int, t: int, p: Vector2) -> void:
	var arr = _enemy_pos_history.get(net_id)
	if arr == null:
		arr = []
		_enemy_pos_history[net_id] = arr
	arr.append({"t": t, "p": p})
	while arr.size() > HIT_HISTORY_MAX:
		arr.remove_at(0)


# 轻量命中校验：目标存活 + 攻击者距离 + 客户端所见位置与 host 历史轨迹相符（favor-the-shooter）
func _validate_enemy_hit(enemy: Node, attacker: int, victim_pos: Vector2) -> bool:
	if enemy.get("stats") != null and enemy.stats != null and int(enemy.stats.hp) <= 0:
		return false
	var ap = _local_or_remote_player(attacker)
	if ap is Node2D and enemy is Node2D:
		if (ap as Node2D).global_position.distance_to((enemy as Node2D).global_position) > HIT_VALIDATE_MAX_DIST:
			return false
	# 回滚合理性：仅当客户端上报了有效位置且 host 有历史时校验（(0,0) 视为未同步 → 跳过，避免误伤）
	if victim_pos.length_squared() > 1.0 and enemy is Node2D and enemy.has_meta("net_id"):
		var expected: Vector2 = _enemy_expected_pos(int(enemy.get_meta("net_id")))
		if expected != Vector2.INF and victim_pos.distance_to(expected) > HIT_VALIDATE_TOL:
			return false
	return true


# 估算攻击者视角时刻该敌人的位置（host 历史中最接近 now - (rtt/2 + 插值延迟) 的点）
func _enemy_expected_pos(net_id: int) -> Vector2:
	var arr = _enemy_pos_history.get(net_id)
	if arr == null or arr.is_empty():
		return Vector2.INF
	var interp_ms: float = SnapshotBuffer.compute_delay(ENEMY_SNAPSHOT_INTERVAL, net_rtt_ms, net_jitter_ms) * 1000.0
	var target_t: int = Time.get_ticks_msec() - int(net_rtt_ms * 0.5 + interp_ms)
	var best_p: Vector2 = Vector2.INF
	var best_dt: int = 1 << 30
	for e in arr:
		var dt: int = absi(int(e["t"]) - target_t)
		if dt < best_dt:
			best_dt = dt
			best_p = e["p"]
	return best_p


# ---------------- 子弹/视觉同步 ----------------

func _flush_visuals() -> void:
	if not _pending_visual.is_empty():
		var batch: Array = _pending_visual.duplicate()
		_pending_visual.clear()
		_send_visual_batches(batch, "_spawn_visual_bullet_batch", "_server_visual_bullet_batch")
	if not _pending_visual_reliable.is_empty():
		var rbatch: Array = _pending_visual_reliable.duplicate()
		_pending_visual_reliable.clear()
		_send_visual_batches(rbatch, "_spawn_visual_bullet_reliable_batch", "_server_visual_bullet_reliable_batch")
	if not _pending_effects.is_empty():
		var ebatch: Array = _pending_effects.duplicate()
		_pending_effects.clear()
		_send_visual_batches(ebatch, "_spawn_visual_effect_batch", "_server_visual_effect_batch")


# 按 BULLET_BATCH_LIMIT 切包发送，避免单包过大超 MTU/被丢整批
func _send_visual_batches(batch: Array, remote_method: String, server_method: String) -> void:
	var i: int = 0
	var n: int = batch.size()
	while i < n:
		var chunk: Array = batch.slice(i, mini(i + BULLET_BATCH_LIMIT, n))
		if multiplayer.is_server():
			rpc(remote_method, chunk)
		else:
			rpc_id(1, server_method, chunk)
		i += BULLET_BATCH_LIMIT


func _spawn_one_effect(e) -> void:
	if not (e is Dictionary):
		return
	if not remote_effect_allowed(StringName("eff:" + str(e.get("s", "")))):
		return
	_visual.spawn_visual_effect(
		get_tree(),
		str(e.get("s", "")),
		e.get("p", Vector2.ZERO),
		float(e.get("r", 0.0)),
		e.get("sc", Vector2.ONE),
		str(e.get("g", "SELayer")),
		str(e.get("m", "active_state")),
		e.get("pr", {})
	)


@rpc("authority", "call_remote", "reliable")
func _spawn_visual_effect_batch(batch: Array) -> void:
	if net_diag_enabled:
		net_effect_recv += batch.size()
	for e in batch:
		_spawn_one_effect(e)


@rpc("any_peer", "call_remote", "reliable")
func _server_visual_effect_batch(batch: Array) -> void:
	if not multiplayer.is_server():
		return
	if net_diag_enabled:
		net_effect_sent += batch.size()
	for e in batch:
		_spawn_one_effect(e)
	var sender: int = multiplayer.get_remote_sender_id()
	for peer in multiplayer.get_peers():
		if peer != sender:
			rpc_id(peer, "_spawn_visual_effect_batch", batch)


func _spawn_one_visual(e) -> void:
	if not (e is Dictionary):
		return
	if not remote_effect_allowed(StringName("vis:" + str(e.get("s", "")))):
		return
	var comp: Array = _compensate_bullet_spawn(e)
	_visual.spawn_visual_bullet(
		get_tree(),
		str(e.get("s", "")),
		comp[0],
		float(e.get("r", 0.0)),
		float(e.get("sp", 0.0)),
		e.get("sc", Vector2.ONE),
		int(comp[1]),
		str(e.get("id", "")),
		e,
		str(e.get("pre", "")),
		str(e.get("m", "active_state"))
	)


# 直线弹网络延迟补偿：按单向延迟把生成位置沿朝向前推、并扣减对应 kill_time。
# 仅对匀速直行弹生效；追踪(homing)/减速(slow_down/decay_time)/反弹(can_r/collision_num) 原样（前推会失真）。
func _compensate_bullet_spawn(e: Dictionary) -> Array:
	var p: Vector2 = e.get("p", Vector2.ZERO)
	var k: int = int(e.get("k", 0))
	var sp: float = float(e.get("sp", 0.0))
	if sp <= 0.0 or not is_finite(p.x) or not is_finite(p.y):
		return [p, k]
	var pr = e.get("pr", {})
	if not (pr is Dictionary):
		pr = {}
	if bool(pr.get("homing", false)) or bool(pr.get("slow_down", false)) \
			or int(pr.get("decay_time", 0)) != 0 or bool(pr.get("can_r", false)) \
			or int(pr.get("collision_num", 0)) != 0:
		return [p, k]
	var delay_s: float = clampf(net_rtt_ms * 0.5 / 1000.0, 0.0, 0.25)
	if delay_s <= 0.0:
		return [p, k]
	p = p + Vector2.RIGHT.rotated(float(e.get("r", 0.0))) * sp * delay_s
	k = maxi(1, k - int(delay_s * 10.0))
	return [p, k]


@rpc("authority", "call_remote", "unreliable")
func _spawn_visual_bullet_batch(batch: Array) -> void:
	if net_diag_enabled:
		net_bullet_recv += batch.size()
	for e in batch:
		_spawn_one_visual(e)


@rpc("any_peer", "call_remote", "unreliable")
func _server_visual_bullet_batch(batch: Array) -> void:
	if not multiplayer.is_server():
		return
	if net_diag_enabled:
		net_bullet_sent += batch.size()
	for e in batch:
		_spawn_one_visual(e)
	var sender: int = multiplayer.get_remote_sender_id()
	for peer in multiplayer.get_peers():
		if peer != sender:
			rpc_id(peer, "_spawn_visual_bullet_batch", batch)


# 一次性关键投射物（打 coop_reliable_visual meta）：可靠批量
@rpc("authority", "call_remote", "reliable")
func _spawn_visual_bullet_reliable_batch(batch: Array) -> void:
	if net_diag_enabled:
		net_bullet_recv += batch.size()
	for e in batch:
		_spawn_one_visual(e)


@rpc("any_peer", "call_remote", "reliable")
func _server_visual_bullet_reliable_batch(batch: Array) -> void:
	if not multiplayer.is_server():
		return
	if net_diag_enabled:
		net_bullet_sent += batch.size()
	for e in batch:
		_spawn_one_visual(e)
	var sender: int = multiplayer.get_remote_sender_id()
	for peer in multiplayer.get_peers():
		if peer != sender:
			rpc_id(peer, "_spawn_visual_bullet_reliable_batch", batch)


@rpc("authority", "call_remote", "reliable")
func _despawn_visual_bullet(sync_id: String) -> void:
	if multiplayer.is_server():
		return
	_visual.despawn_visual_bullet(sync_id)


@rpc("any_peer", "call_remote", "reliable")
func _server_despawn_visual_bullet(sync_id: String) -> void:
	if not multiplayer.is_server():
		return
	_visual.despawn_visual_bullet(sync_id)
	var sender: int = multiplayer.get_remote_sender_id()
	for peer in multiplayer.get_peers():
		if peer != sender:
			rpc_id(peer, "_despawn_visual_bullet", sync_id)


# 开发/测试：本地生成一发普通子弹（经 ProjectileSpawner → 触发广播）。
func dev_spawn_bullet() -> void:
	var scene := load("res://scenes/bullet/normal_bullet.tscn") as PackedScene
	if scene == null:
		return
	var p := get_local_player()
	var pos: Vector2 = p.global_position if p != null else Vector2.ZERO
	ProjectileSpawner.spawn_core(scene, "normal_bullet", "BulletRoot", self, Faction.PLAYER_SIDE, pos, 0.0, Vector2.ZERO, false, false, true)


func dev_visual_count() -> int:
	return _visual.total()


# 开发/测试：本地生成一个爆炸特效（经 ProjectileSpawner → 触发特效广播）。
func dev_spawn_effect() -> void:
	var scene := load("res://script/explosion_damage.tscn") as PackedScene
	if scene == null:
		return
	var p := get_local_player()
	var pos: Vector2 = p.global_position if p != null else Vector2.ZERO
	ProjectileSpawner.spawn_core(scene, "player_explosion", "BulletRoot", self, Faction.PLAYER_SIDE, pos, 0.0, Vector2.ZERO, true, false, true, Callable(self, "_dev_configure_explosion"))


func _dev_configure_explosion(node: Node) -> void:
	node.explosion_range = 5.0


func dev_effect_count() -> int:
	return _visual.effect_count()


# 开发/测试：服务端在本地玩家旁掉一枚金币。
func dev_spawn_coin(value: int) -> void:
	if not is_lan_game or not multiplayer.is_server():
		return
	var p := get_local_player()
	var pos: Vector2 = (p.global_position + Vector2(200, 0)) if p != null else Vector2.ZERO
	CoinManager.drop_coin(pos, value, false)


# 开发/测试：客户端拾取一枚（走 gate → 请求服务端共享）。
func dev_pickup_coin() -> void:
	if not is_lan_game or multiplayer.is_server():
		return
	for net_id in coin_by_net_id.keys():
		var c = coin_by_net_id[net_id]
		if c != null and is_instance_valid(c) and c.has_method("add_coin"):
			c.add_coin()
			return


func dev_player_coins() -> int:
	var p := get_local_player()
	if p == null or p.get("stats") == null:
		return -1
	return int(p.stats.coin)


# 开发/测试：本地生成一个召唤物（触发 on_summoned_spawned → 广播）。
func dev_spawn_summoned() -> void:
	if not is_lan_game:
		return
	var scene := load("res://scenes/summoned/mobu_trinity/mobu_trinity.tscn") as PackedScene
	if scene == null:
		return
	var root := _summoned_root()
	if root == null:
		return
	var p := get_local_player()
	var s: Node = scene.instantiate()
	root.add_child(s)
	s.global_position = (p.global_position + Vector2(-20, 0)) if p != null else Vector2.ZERO
	if s.has_method("active_state"):
		s.active_state()


func dev_summoned_count() -> int:
	return summoned_by_net_id.size()


func dev_set_local_hp(v: int) -> void:
	var p := get_local_player()
	if p != null and p.get("stats") != null:
		p.stats.hp = v


func dev_local_downed() -> bool:
	var p := get_local_player()
	return p != null and p.get("is_downed") != null and p.is_downed


func dev_remote_downed_count() -> int:
	var n: int = 0
	for p in player_by_peer_id.values():
		if p != null and is_instance_valid(p) and p.get("is_downed") != null and p.is_downed:
			n += 1
	return n


func dev_rescue_prompt_shown() -> bool:
	return _rescue_prompt_shown


func dev_emit_boss_event() -> void:
	GameEvents.emit_boss_event("dev_test", {})


func dev_boss_events_received() -> int:
	return boss_events_received


func dev_local_hp() -> int:
	var p := get_local_player()
	if p == null or p.get("stats") == null:
		return -1
	return int(p.stats.hp)


# 开发/测试：验证 LAN 暂停语义（只停本地玩家，不暂停世界）
func dev_pause_probe() -> void:
	var p := get_local_player()
	if p == null or not is_instance_valid(p):
		print("[etn_coop] dev-pause: no local player")
		return
	var ps: Node = p.get("pause_screen")
	if ps == null:
		print("[etn_coop] dev-pause: no pause_screen")
		return
	print("[etn_coop] dev-pause before: paused=%s player_stop=%s vis=%s lan=%s" % [
		str(get_tree().paused), str(p.get("player_stop")), str(ps.visible), str(is_lan_game)])
	ps.call("show_pause")
	await get_tree().process_frame
	await get_tree().process_frame
	print("[etn_coop] dev-pause open: paused=%s player_stop=%s meta=%s process_mode=%s" % [
		str(get_tree().paused), str(p.get("player_stop")),
		str(p.get_meta("pause_menu_open", false)), str(ps.get("process_mode"))])
	ps.call("hide_pause_screen")
	await get_tree().process_frame
	await get_tree().process_frame
	print("[etn_coop] dev-pause closed: paused=%s player_stop=%s meta=%s" % [
		str(get_tree().paused), str(p.get("player_stop")), str(p.get_meta("pause_menu_open", false))])
	# 复现团队结束路径：本体 crosshair/UP 面板应已通过 get_player 拿到本地玩家
	var crosshair: Node = null
	var scene := get_tree().current_scene
	if scene != null:
		for n in scene.find_children("*", "Node2D", true, false):
			var s: Variant = n.get_script()
			if s != null and str(s.resource_path).ends_with("crosshair.gd"):
				crosshair = n
				break
	print("[etn_coop] dev-pause crosshair player=%s" % str(crosshair.get("player") if crosshair != null else null))
	GameEvents.emit_game_over(true)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[etn_coop] dev-pause team game over emitted (no crash => ok)")


# 开发/测试：在当前玩家处生成一座"敌方视觉激光"（本地表现端），验证伤害洞。
func dev_spawn_visual_laser_on_self() -> void:
	var p := get_local_player()
	if p == null:
		return
	_visual.spawn_visual_effect(
		get_tree(),
		"res://scenes/bullet/launcher/laser_launcher.tscn",
		p.global_position,
		0.0,
		Vector2.ONE,
		"SELayer",
		"active_state",
		{"source_faction": Faction.ENEMY_SIDE}
	)


# 开发/测试：本地生成一座激光发射器并激活（走 notify_local → 特效广播）。
func dev_spawn_laser() -> void:
	var scene := load("res://scenes/bullet/launcher/laser_launcher.tscn") as PackedScene
	if scene == null:
		return
	var root := get_tree().get_first_node_in_group("PlayerRoot")
	if root == null:
		root = get_tree().get_first_node_in_group("SELayer")
	if root == null:
		return
	var l: Node = scene.instantiate()
	root.add_child(l)
	var p := get_local_player()
	if p != null and l is Node2D:
		(l as Node2D).global_position = p.global_position + Vector2(200, 0)
	if l.has_method("active_state"):
		l.call("active_state")


# ---------------- 金币同步（服务端权威 + 共享增益） ----------------

func _do_shared_coin_pickup(net_id: int, value: int, pos: Vector2, coin_node: Node) -> void:
	if coin_node != null and is_instance_valid(coin_node) and coin_node.has_method("idle_state"):
		coin_node.idle_state()
	if net_id >= 0:
		coin_by_net_id.erase(net_id)
		rpc("_despawn_coin_remote", net_id, multiplayer.get_unique_id())
	_apply_shared_coin_local(value, pos)
	rpc("_apply_shared_coin_remote", value, pos)


func _apply_shared_coin_local(value: int, pos: Vector2) -> void:
	var p := get_local_player()
	if p == null or p.get("stats") == null:
		return
	p.stats.coin += value
	if p.get("coin_sounds") != null:
		p.coin_sounds.play()
	GameEvents.emit_player_pick_up_coin(pos)
	GameEvents.emit_player_coins_get(value)


@rpc("authority", "call_remote", "reliable")
func _spawn_coin_remote(net_id: int, position: Vector2, value: int, pick_up: bool) -> void:
	if multiplayer.is_server() or coin_by_net_id.has(net_id):
		return
	var root := get_tree().get_first_node_in_group("CoinRoot")
	if root == null:
		return
	var scene := load("res://scenes/item/coin.tscn") as PackedScene
	if scene == null:
		return
	var c: Node = scene.instantiate()
	root.add_child(c)
	c.global_position = position
	c.coin = value
	c.pick_up = pick_up
	c.set_meta("net_id", net_id)
	c.active_state()
	coin_by_net_id[net_id] = c


@rpc("authority", "call_remote", "reliable")
func _despawn_coin_remote(net_id: int, picker_peer: int) -> void:
	if multiplayer.is_server():
		return
	var c = coin_by_net_id.get(net_id)
	coin_by_net_id.erase(net_id)
	if c != null and is_instance_valid(c):
		_play_coin_pickup_visual(c, picker_peer)


@rpc("any_peer", "call_remote", "reliable")
func _server_pickup_coin(net_id: int, value: int, pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var c = coin_by_net_id.get(net_id)
	if c != null and is_instance_valid(c) and c.has_method("idle_state"):
		c.idle_state()
	if net_id >= 0:
		coin_by_net_id.erase(net_id)
		rpc("_despawn_coin_remote", net_id, multiplayer.get_remote_sender_id())
	_apply_shared_coin_local(value, pos)
	rpc("_apply_shared_coin_remote", value, pos)


@rpc("authority", "call_remote", "reliable")
func _apply_shared_coin_remote(value: int, pos: Vector2) -> void:
	_apply_shared_coin_local(value, pos)


# ---------------- 远程表现（对齐联机版） ----------------

func _play_remote_enemy_spawn_anim(position: Vector2) -> void:
	if not is_lan_game:
		return
	var root := get_tree().get_first_node_in_group("EnemiesRoot")
	if root == null:
		return
	var scene := load("res://script/spawn_anim.tscn") as PackedScene
	if scene == null:
		return
	var anim := scene.instantiate()
	root.add_child(anim)
	if anim is Node2D:
		(anim as Node2D).global_position = position
	anim.set_meta("remote_visual", true)
	if anim.has_method("remote_spawn_anim"):
		anim.call("remote_spawn_anim")
	else:
		if anim.has_method("active_state"):
			anim.call("active_state")
		var ap = anim.get("animation_player")
		if ap != null and ap.has_method("play"):
			ap.call("play", "new_animation")
	_queue_free_later(anim, 3.0)


func _queue_free_later(node: Node, delay: float) -> void:
	if node == null:
		return
	var ref: WeakRef = weakref(node)
	await get_tree().create_timer(delay).timeout
	var n = ref.get_ref()
	if n != null and is_instance_valid(n):
		n.queue_free()


func _play_remote_scene_transition_start() -> void:
	var transition := get_node_or_null("/root/Transition")
	if transition == null or not transition.has_method("play_left_start"):
		return
	if transition.get("is_left_end_start") == true:
		return
	transition.call("play_left_start")
	await transition.left_end_start


func _play_coin_pickup_visual(coin_node: Node, picker_peer: int) -> void:
	if coin_node == null or not is_instance_valid(coin_node):
		return
	var target := _local_or_remote_player(picker_peer)
	if target == null or not is_instance_valid(target):
		if coin_node.has_method("idle_state"):
			coin_node.call("idle_state")
		else:
			coin_node.queue_free()
		return
	var cs = coin_node.get("collision_shape_2d")
	if cs is CollisionShape2D:
		(cs as CollisionShape2D).set_deferred("disabled", true)
	coin_node.set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(coin_node, "global_position", target.global_position, 0.18)
	await tween.finished
	if is_instance_valid(coin_node):
		if coin_node.has_method("idle_state"):
			coin_node.call("idle_state")
		else:
			coin_node.queue_free()


# ---------------- 召唤物同步（拥有者权威） ----------------

func send_summoned_state(net_id: int, position: Vector2, velocity: Vector2, rotation: float) -> void:
	if not is_lan_game:
		return
	if multiplayer.is_server():
		rpc("_summoned_state_remote", net_id, position, velocity, rotation)
	else:
		rpc_id(1, "_server_summoned_state", net_id, position, velocity, rotation)


func request_summoned_despawn(net_id: int) -> void:
	if not is_lan_game:
		return
	if multiplayer.is_server():
		_despawn_summoned_local(net_id)
		rpc("_despawn_summoned_remote", net_id)
	else:
		rpc_id(1, "_server_summoned_despawn", net_id)


func _despawn_summoned_local(net_id: int) -> void:
	if not summoned_by_net_id.has(net_id):
		return
	var s = summoned_by_net_id[net_id]
	if s != null and is_instance_valid(s):
		if s.has_method("idle_state"):
			s.idle_state()
		else:
			s.queue_free()
	summoned_by_net_id.erase(net_id)
	summoned_proxy_by_net_id.erase(net_id)
	summoned_scene_by_net_id.erase(net_id)
	summoned_owner_by_net_id.erase(net_id)


func _attach_summoned_proxy(summoned: Node, net_id: int, owner_peer: int, is_local_owner: bool) -> void:
	var proxy: Node = SummonedProxyScript.new()
	proxy.name = "CoopSummonedProxy"
	summoned.add_child(proxy)
	proxy.setup(net_id, owner_peer, is_local_owner)
	summoned_proxy_by_net_id[net_id] = proxy


func _summoned_root(scene_path: String = "") -> Node:
	var t := get_tree()
	if t == null:
		return null
	# 无人机镜像挂 EquipLayer（与本体一致）
	if scene_path.contains("shiroko_drone"):
		var eq := t.get_first_node_in_group("EquipLayer")
		if eq != null:
			return eq
	var r := t.get_first_node_in_group("PlayerRoot")
	if r == null:
		r = t.get_first_node_in_group("SELayer")
	return r


@rpc("authority", "call_remote", "reliable")
func _spawn_summoned_remote(net_id: int, owner_peer: int, scene_path: String, position: Vector2, rotation: float) -> void:
	if multiplayer.is_server():
		return
	# 拥有者本地实体认领（避免双份）
	if owner_peer == multiplayer.get_unique_id():
		var local := _consume_pending_local_summon(scene_path)
		if local != null:
			_register_local_summoned(local, net_id, owner_peer, scene_path)
			return
	_spawn_summoned_local(net_id, owner_peer, scene_path, position, rotation)


@rpc("any_peer", "call_remote", "reliable")
func _server_summoned_spawn(net_id: int, owner_peer: int, scene_path: String, position: Vector2, rotation: float) -> void:
	if not multiplayer.is_server():
		return
	_spawn_summoned_local(net_id, owner_peer, scene_path, position, rotation)
	var sender: int = multiplayer.get_remote_sender_id()
	for peer in multiplayer.get_peers():
		if peer != sender:
			rpc_id(peer, "_spawn_summoned_remote", net_id, owner_peer, scene_path, position, rotation)


func _spawn_summoned_local(net_id: int, owner_peer: int, scene_path: String, position: Vector2, rotation: float) -> void:
	if summoned_by_net_id.has(net_id):
		return
	var root := _summoned_root(scene_path)
	var scene := load(scene_path) as PackedScene
	if root == null or scene == null:
		return
	var s: Node = scene.instantiate()
	s.set_meta("remote_summoned", true)
	root.add_child(s)
	s.global_position = position
	s.global_rotation = rotation
	_attach_summoned_proxy(s, net_id, owner_peer, false)
	if s.has_method("active_state"):
		s.active_state()
	summoned_by_net_id[net_id] = s
	summoned_scene_by_net_id[net_id] = scene_path
	summoned_owner_by_net_id[net_id] = owner_peer


@rpc("authority", "call_remote", "reliable")
func _despawn_summoned_remote(net_id: int) -> void:
	if multiplayer.is_server():
		return
	_despawn_summoned_local(net_id)


@rpc("any_peer", "call_remote", "unreliable")
func _server_summoned_state(net_id: int, position: Vector2, velocity: Vector2, rotation: float) -> void:
	if not multiplayer.is_server():
		return
	_summoned_state_remote(net_id, position, velocity, rotation)
	var sender: int = multiplayer.get_remote_sender_id()
	for peer in multiplayer.get_peers():
		if peer != sender:
			rpc_id(peer, "_summoned_state_remote", net_id, position, velocity, rotation)


@rpc("authority", "call_remote", "unreliable")
func _summoned_state_remote(net_id: int, position: Vector2, velocity: Vector2, rotation: float) -> void:
	var proxy = summoned_proxy_by_net_id.get(net_id)
	if proxy != null and is_instance_valid(proxy) and proxy.has_method("apply_state"):
		proxy.apply_state(position, velocity, rotation)


@rpc("any_peer", "call_remote", "reliable")
func _server_summoned_despawn(net_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if int(summoned_owner_by_net_id.get(net_id, -1)) != sender:
		return
	_despawn_summoned_local(net_id)
	rpc("_despawn_summoned_remote", net_id)


func _send_existing_summons_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	for net_id in summoned_by_net_id.keys():
		var s = summoned_by_net_id[net_id]
		if s == null or not is_instance_valid(s):
			continue
		var scene_path: String = str(summoned_scene_by_net_id.get(net_id, ""))
		if scene_path == "":
			continue
		var owner_peer: int = int(summoned_owner_by_net_id.get(net_id, 1))
		rpc_id(peer_id, "_spawn_summoned_remote", net_id, owner_peer, scene_path, s.global_position, s.global_rotation)


# ---------------- 倒地/救援 ----------------

func _update_rescue(delta: float) -> void:
	var p := get_local_player()
	if p == null:
		_hide_rescue_prompt()
		return
	if p.get("is_downed") != null and p.is_downed:
		_rescue_target = null
		_rescue_hold = 0.0
		_hide_rescue_prompt()
		return
	var target := _find_downed_ally()
	if target == null:
		_rescue_target = null
		_rescue_hold = 0.0
		_hide_rescue_prompt()
		return
	if target != _rescue_target:
		_rescue_target = target
		_rescue_hold = 0.0
	if Input.is_action_pressed("use"):
		_rescue_hold += delta
		if _rescue_hold >= RESCUE_TIME:
			_rescue_hold = 0.0
			var tid: int = int(target.get_meta("peer_id")) if target.has_meta("peer_id") else -1
			if tid > 0:
				request_revive_player(tid)
	else:
		_rescue_hold = maxf(0.0, _rescue_hold - delta * 2.0)
	_show_rescue_prompt(target, _rescue_hold)


func _rescue_text(key: String, fallback: String) -> String:
	var t: String = tr(key)
	if t.is_empty() or t == key:
		return fallback
	return t


func _ensure_rescue_prompt() -> Node:
	if _rescue_prompt != null and is_instance_valid(_rescue_prompt):
		return _rescue_prompt
	if _rescue_prompt_scene == null:
		_rescue_prompt_scene = load("res://scenes/manager/interact_prompt.tscn") as PackedScene
	if _rescue_prompt_scene == null:
		return null
	var prompt: Node = _rescue_prompt_scene.instantiate()
	var parent: Node = null
	var p := get_local_player()
	if p != null:
		parent = p.get_parent()
	if parent == null:
		parent = get_tree().get_first_node_in_group("SELayer")
	if parent == null:
		return null
	parent.add_child(prompt)
	_rescue_prompt = prompt
	return _rescue_prompt


func _show_rescue_prompt(target: Node, hold: float) -> void:
	var prompt := _ensure_rescue_prompt()
	if prompt == null or not (target is Node2D):
		return
	var text: String = _rescue_text("lan_rescue_prompt", "RESCUE")
	if hold > 0.0:
		text = "%s %d%%" % [text, int(round(hold / RESCUE_TIME * 100.0))]
	var world_pos: Vector2 = (target as Node2D).global_position + Vector2.UP * 24.0
	if prompt.has_method("show_prompt"):
		prompt.call("show_prompt", text, world_pos)
	_rescue_prompt_shown = true


func _hide_rescue_prompt() -> void:
	if not _rescue_prompt_shown:
		return
	_rescue_prompt_shown = false
	if _rescue_prompt != null and is_instance_valid(_rescue_prompt) and _rescue_prompt.has_method("hide_prompt"):
		_rescue_prompt.call("hide_prompt")


func _find_downed_ally() -> Node:
	var p := get_local_player()
	if p == null:
		return null
	var nearest: Node = null
	var nearest_distance: float = RESCUE_RADIUS
	for c in get_tree().get_nodes_in_group("RemotePlayer"):
		if c == null or not is_instance_valid(c) or not (c is Node2D):
			continue
		if c.get("is_downed") == null or not c.is_downed:
			continue
		var d: float = p.global_position.distance_to((c as Node2D).global_position)
		if d <= nearest_distance:
			nearest_distance = d
			nearest = c
	return nearest


func request_revive_player(target_peer_id: int) -> void:
	if not is_lan_game:
		return
	if multiplayer.is_server():
		_server_try_revive(multiplayer.get_unique_id(), target_peer_id)
	else:
		rpc_id(1, "_server_request_revive", target_peer_id)


func _server_try_revive(requester: int, target: int) -> void:
	if not multiplayer.is_server():
		return
	if requester == target:
		return
	if not down_peer_ids.get(target, false):
		return
	var req: Node = _local_or_remote_player(requester)
	var tgt: Node = _local_or_remote_player(target)
	if req == null or tgt == null:
		return
	# 请求者必须存活、未倒地
	if req.get("is_downed") != null and req.is_downed:
		return
	if req.get("stats") != null and req.stats != null and int(req.stats.hp) <= 0:
		return
	# 距离校验
	if req is Node2D and tgt is Node2D:
		if (req as Node2D).global_position.distance_to((tgt as Node2D).global_position) > RESCUE_RADIUS:
			return
	down_peer_ids.erase(target)
	rpc("_remote_revived", target, REVIVE_HEALTH_MULT)
	_apply_revive_local(target, REVIVE_HEALTH_MULT)


func _local_or_remote_player(peer_id: int) -> Node:
	if peer_id == multiplayer.get_unique_id():
		return get_local_player()
	var p = player_by_peer_id.get(peer_id)
	if p != null and is_instance_valid(p):
		return p
	return null


func _apply_revive_local(peer_id: int, mult: float) -> void:
	var p: Node = null
	if peer_id == multiplayer.get_unique_id():
		p = get_local_player()
	else:
		p = player_by_peer_id.get(peer_id)
	if p == null or not is_instance_valid(p):
		return
	if p.has_method("set_downed_state"):
		p.set_downed_state(false)
	if peer_id == multiplayer.get_unique_id():
		_hide_motion_down()
	if p.get("stats") != null and p.stats != null:
		if p.stats.get("player_dead") != null:
			p.stats.player_dead = false
		p.stats.hp = maxi(1, int(round(float(p.stats.max_hp) * mult)))


@rpc("authority", "call_remote", "reliable")
func _remote_player_down_changed(peer_id: int, is_down: bool) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var p = player_by_peer_id.get(peer_id)
	if p != null and is_instance_valid(p) and p.has_method("set_downed_state"):
		p.set_downed_state(is_down)


@rpc("any_peer", "call_remote", "reliable")
func _server_player_down() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	down_peer_ids[sender] = true
	rpc("_remote_player_down_changed", sender, true)
	_remote_player_down_changed(sender, true)
	_check_team_game_over()


@rpc("any_peer", "call_remote", "reliable")
func _server_player_up() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	down_peer_ids.erase(sender)
	rpc("_remote_player_down_changed", sender, false)
	_remote_player_down_changed(sender, false)


@rpc("any_peer", "call_remote", "reliable")
func _server_request_revive(target_peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var requester: int = multiplayer.get_remote_sender_id()
	_server_try_revive(requester, target_peer_id)


@rpc("authority", "call_remote", "reliable")
func _remote_revived(peer_id: int, mult: float) -> void:
	_apply_revive_local(peer_id, mult)


# ---------------- 团队流程（game over / 回合升级就绪） ----------------

func _all_peers_down() -> bool:
	var expected: Array = [1]
	for p in multiplayer.get_peers():
		expected.append(p)
	for pid in expected:
		if not down_peer_ids.get(pid, false):
			return false
	return true


func _check_team_game_over() -> void:
	if not multiplayer.is_server() or team_game_over_forced or not battle_active:
		return
	if not _all_peers_down():
		return
	_force_team_game_over_authoritative(true)


func _force_team_game_over_authoritative(player_dead: bool) -> void:
	if not multiplayer.is_server():
		return
	if team_game_over_forced:
		return
	team_game_over_forced = true
	get_tree().paused = false
	rpc("_force_team_game_over", player_dead)
	GameEvents.force_emit_game_over(player_dead)


@rpc("any_peer", "call_remote", "reliable")
func _server_request_team_game_over(player_dead: bool) -> void:
	if not multiplayer.is_server():
		return
	_force_team_game_over_authoritative(player_dead)


func _maybe_finish_round_upgrade() -> void:
	if not multiplayer.is_server():
		return
	var expected: Array = [1]
	for p in multiplayer.get_peers():
		expected.append(p)
	for pid in expected:
		if not round_upgrade_ready_peers.get(pid, false):
			return
	round_upgrade_ready_peers.clear()
	rpc("_remote_round_upgrade_end")
	GameEvents.force_round_upgrade_end()


@rpc("authority", "call_remote", "reliable")
func _force_team_game_over(player_dead: bool) -> void:
	team_game_over_forced = true
	get_tree().paused = false
	GameEvents.force_emit_game_over(player_dead)


@rpc("any_peer", "call_remote", "reliable")
func _server_round_upgrade_ready() -> void:
	if not multiplayer.is_server():
		return
	var pid: int = multiplayer.get_remote_sender_id()
	round_upgrade_ready_peers[pid] = true
	rpc("_remote_round_upgrade_ready_changed", pid, true)
	_maybe_finish_round_upgrade()


# 升级页"队友已就绪"指示：映射到本端视角的槽位（排除自己）后发给 UI
@rpc("authority", "call_remote", "reliable")
func _remote_round_upgrade_ready_changed(peer_id: int, is_ready: bool) -> void:
	var slot: int = _upgrade_slot_for(peer_id)
	if slot >= 0:
		GameEvents.emit_upgrade_ready_changed(slot, is_ready)


func _upgrade_slot_for(peer_id: int) -> int:
	var local_id: int = multiplayer.get_unique_id()
	var ids: Array = [local_id]
	ids.append_array(multiplayer.get_peers())
	ids.sort()
	var others: Array = []
	for id in ids:
		if int(id) != local_id:
			others.append(id)
	var idx: int = others.find(peer_id)
	return (idx + 1) if idx >= 0 else -1


@rpc("authority", "call_remote", "reliable")
func _remote_round_upgrade_end() -> void:
	GameEvents.force_round_upgrade_end()


# ---------------- 场景切换广播 ----------------

@rpc("any_peer", "call_remote", "reliable")
func _server_player_selected(player_scene: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	selected_player_scene_by_peer[sender] = player_scene
	player_scene_by_peer[sender] = player_scene
	print("[etn_coop] peer %d selected %s" % [sender, player_scene])
	# 新流程：准备房选人阶段只记录，由房主选完难度后统一开战（见 begin_battle / change_scene gate）
	if _select_flow_active:
		return
	if not _all_expected_selected():
		return
	# 已开打（中途加入）：不重载整局（否则会触发 first_round/reset_data 清空 host 进度与属性），
	# 只让新玩家进入当前场景，并为其补生在局玩家镜像与已存在敌人/召唤物。
	if battle_active and current_scene_path != "":
		print("[etn_coop] mid-run join: peer %d -> %s (no session reload)" % [sender, current_scene_path])
		rpc_id(sender, "_remote_change_scene", current_scene_path, player_scene_by_peer, _build_level_state())
		for other in multiplayer.get_peers():
			if other != sender:
				rpc_id(other, "_spawn_remote_player", sender, player_scene)
		spawn_remote_player(sender, player_scene)
		return
	# 开局前全员选定：由 host 放行本体加载
	_broadcast_roster()
	_force_release = true
	GameEvents.change_scene(_pending_scene_path, local_player_scene_path)


@rpc("authority", "call_remote", "reliable")
func _remote_change_scene(path: String, roster: Dictionary, level_state: Dictionary = {}) -> void:
	if multiplayer.is_server():
		return
	# 离开选人/准备房前先解除暂停，保证转场与目标场景正常运行
	_set_select_pause(false)
	# 复刻 host 的场景切换转场（左划开始 → 结束再真正切场景）
	await _play_remote_scene_transition_start()
	_applying_change = true
	_reset_player_sync()
	first_round_emitted = false
	_apply_level_state(level_state)
	player_scene_by_peer = roster.duplicate()
	if roster.is_empty():
		GameEvents.change_scene(path, "")
	else:
		var own: String = str(roster.get(multiplayer.get_unique_id(), DEFAULT_PLAYER_SCENE))
		GameEvents.change_scene(path, own)
	_applying_change = false
	await get_tree().process_frame
	rpc_id(1, "_client_scene_ready")


@rpc("any_peer", "call_remote", "reliable")
func _client_scene_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	scene_ready_peers[sender] = true
	# 客机场景已就绪：补发 roster + 已存在的敌人/召唤物（对齐联机版 _mark_scene_ready）
	if battle_active:
		rpc_id(sender, "_client_sync_roster", player_scene_by_peer)
		_send_existing_enemies_to_peer(sender)
		_send_existing_summons_to_peer(sender)
		# host 侧也补生远端镜像（覆盖被 reset_clear_unit 清掉的情况）
		_respawn_remote_players()


@rpc("authority", "call_remote", "reliable")
func _remote_return_to_menu(path: String) -> void:
	if multiplayer.is_server():
		return
	# 交给 change_scene_gate 的 player=="" 分支统一复位 run state 并放行本体加载
	GameEvents.change_scene(path, "")


# ---------------- 受击反馈（非拥有端） ----------------

func _on_local_player_hurt(player: Node) -> void:
	if not is_lan_game:
		return
	if player != get_local_player():
		return
	var pid: int = multiplayer.get_unique_id()
	if multiplayer.is_server():
		rpc("_remote_player_hurt", pid)
	else:
		rpc_id(1, "_server_player_hurt")


@rpc("authority", "call_remote", "unreliable")
func _remote_player_hurt(peer_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		return
	var p = player_by_peer_id.get(peer_id)
	if p == null or not is_instance_valid(p):
		return
	# 复刻本体受击路径：start() 计时器 + _on_invincible_frame(true)。
	# 只调 _on_invincible_frame(true) 会把 flash_opacity 停在 0.3，因归零在 _on_invincible_frame_end()
	# （InvincibleFrame.timeout 触发），未启动计时器则远端镜像一直卡闪白。
	var timer = p.get("invincible_frame")
	if timer == null:
		timer = p.get_node_or_null("InvincibleFrame")
	if timer != null and timer.has_method("start"):
		timer.call("start")
	if p.has_method("_on_invincible_frame"):
		p.call("_on_invincible_frame", true)


@rpc("any_peer", "call_remote", "unreliable")
func _server_player_hurt() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	rpc("_remote_player_hurt", sender)
	_remote_player_hurt(sender)


# ---------------- 枪开火后坐（非拥有端复刻） ----------------

# 本机玩家枪开火（镜像枪物理已关不会发），广播给其它端重放 fire_anim
func _on_local_gun_shoot(_gun: Node) -> void:
	if not is_lan_game:
		return
	var pid: int = multiplayer.get_unique_id()
	if multiplayer.is_server():
		rpc("_remote_player_gun_shoot", pid)
	else:
		rpc_id(1, "_server_player_gun_shoot")


@rpc("any_peer", "call_remote", "unreliable")
func _server_player_gun_shoot() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_remote_player_gun_shoot(sender)
	for peer in multiplayer.get_peers():
		if peer != sender:
			rpc_id(peer, "_remote_player_gun_shoot", sender)


@rpc("authority", "call_remote", "unreliable")
func _remote_player_gun_shoot(peer_id: int) -> void:
	if not is_lan_game:
		return
	var p = player_by_peer_id.get(peer_id)
	if p == null or not is_instance_valid(p):
		return
	var g = p.get("gun")
	if g != null and g.has_method("_shootAnim"):
		g.call("_shootAnim")


# host 的自然命中（host 自己/其道具召唤物造成，未抑制）→ 广播给客机回放；host 本地已有自然表现，不重复回放。
func _on_server_enemy_damage_taken(actual_damage: int, damage_data, enemy: Node) -> void:
	if not multiplayer.is_server():
		return
	# 回放反馈时 play_hit_feedback 会 emit damage_taken，而本函数正连在该信号上；
	# 不跳过会再次广播 → 客机对同一次命中收到两条（双飘字）
	if _replaying_feedback:
		return
	if enemy == null or not is_instance_valid(enemy) or not enemy.has_meta("net_id"):
		return
	if not (damage_data is DamageData):
		return
	if actual_damage <= 0:
		return
	var net_id: int = int(enemy.get_meta("net_id"))
	var owner_peer: int = int(damage_data.owner_peer) if int(damage_data.owner_peer) != 0 else multiplayer.get_unique_id()
	last_attacker_by_net_id[net_id] = owner_peer
	_add_team_damage(owner_peer, int(actual_damage))
	var killed: bool = enemy.get("stats") != null and int(enemy.stats.hp) <= 0
	rpc("_remote_hit_feedback", net_id, int(actual_damage), _damage_to_dict(damage_data), owner_peer, false)
	if owner_peer != multiplayer.get_unique_id():
		# 客机归属的持续伤害等（host 自然结算但归属客机）：回传归属端发射 proc（host 端已 suppress_proc）
		rpc_id(owner_peer, "_remote_enemy_proc", net_id, int(actual_damage), _damage_to_dict(damage_data), killed)


# 归属端接收权威命中结果 → 在本机发射 enemy_damage_taken(_dead)，触发归属玩家的道具/PS
@rpc("authority", "call_remote", "reliable")
func _remote_enemy_proc(net_id: int, actual_damage: int, cfg: Dictionary, killed: bool) -> void:
	if multiplayer.is_server():
		return
	var enemy = enemy_by_net_id.get(net_id)
	if enemy == null or not is_instance_valid(enemy):
		return
	if actual_damage <= 0:
		return
	var data: DamageData = DamageData.fill(null, cfg)
	GameEvents.emit_enemy_damage_taken(actual_damage, data, enemy.get_path())
	if killed:
		GameEvents.emit_enemy_damage_taken_dead(actual_damage, data, enemy.get_path())


# ---------------- 命中反馈回放（其它玩家来源可独立调速） ----------------

@rpc("authority", "call_remote", "reliable")
func _remote_hit_feedback(net_id: int, actual_damage: int, cfg: Dictionary, attacker_peer: int, predicted: bool) -> void:
	if multiplayer.is_server():
		return
	# 攻击者已在其命中瞬间本地预测表现（闪白/飘字/血条），跳过回声避免重复
	if predicted and attacker_peer == multiplayer.get_unique_id():
		return
	var enemy = enemy_by_net_id.get(net_id)
	if enemy == null or not is_instance_valid(enemy):
		return
	var data: DamageData = DamageData.fill(null, cfg)
	var is_remote: bool = attacker_peer != multiplayer.get_unique_id()
	_replay_hit_feedback(enemy, data, actual_damage, is_remote)


# 统一回放：闪白 + 飘字 + 通用命中火花。is_remote=true 用"其它玩家"频率门；false 用本体全局门。
func _replay_hit_feedback(enemy: Node, data: DamageData, actual_damage: int, is_remote: bool) -> void:
	if enemy == null or not is_instance_valid(enemy) or actual_damage <= 0:
		return
	var component: Node = _health_component_of(enemy)
	if component == null or not component.has_method("play_hit_feedback"):
		return
	var do_flash: bool
	var do_text: bool
	if is_remote:
		do_flash = remote_flash_allowed(enemy)
		do_text = _remote_text_should_emit()
	else:
		do_flash = PoolManager.hit_flash_allowed(enemy)
		do_text = PoolManager.get_text_tick_skip() > 0
	_replaying_feedback = true
	component.play_hit_feedback(actual_damage, data, do_flash, do_text)
	_replaying_feedback = false
	# 受击音：与本体 health_component 一致（每次命中一次）；远端来源走限流，本地走节流。
	# 子弹烟/爆炸 VFX 由来源广播（_on_any_projectile_hit / _on_explosion_effect），此处不再放通用特效。
	if is_remote:
		if _remote_sfx_allowed("HurtSounds"):
			SoundManager.play_sfx("HurtSounds")
	else:
		SoundManager.play_sfx_throttled("HurtSounds")


# ---------------- 敌人命中预测（对齐联机版） ----------------

func _get_predicted_enemy_damage(enemy: Node, damage: int) -> int:
	if damage <= 0:
		return 0
	var stats = enemy.get("stats") if enemy != null and is_instance_valid(enemy) else null
	var scaled: float = float(maxi(1, damage))
	if stats != null and stats.get("global_hurt_damage") != null:
		scaled *= maxf(0.001, float(stats.get("global_hurt_damage")))
	return maxi(1, int(scaled))


func will_enemy_hit_kill(enemy: Node, damage: int) -> bool:
	if not is_lan_game or multiplayer.is_server() or enemy == null or damage <= 0:
		return false
	if not is_instance_valid(enemy):
		return false
	if bool(enemy.get_meta("network_test_target", false)):
		return false
	var stats = enemy.get("stats")
	if stats == null:
		return false
	var current_hp: int = int(stats.get("hp"))
	var predicted_hp: int = int(enemy.get_meta("predicted_hp", current_hp))
	return predicted_hp - _get_predicted_enemy_damage(enemy, damage) <= 0


# 客机预测致死：镜像即时播死亡演出并 idle；host 快照证未死时由 proxy._revive_local_mirror 复活
func _predict_enemy_death(enemy: Node, damage: int, net_id: int) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.has_meta("predicted_dead") and enemy.get_meta("predicted_dead"):
		return
	var stats = enemy.get("stats")
	if stats == null:
		return
	var predicted_damage: int = _get_predicted_enemy_damage(enemy, damage)
	var predicted_hp: int = 0
	var proxy = enemy_proxy_by_net_id.get(net_id)
	if proxy != null and is_instance_valid(proxy) and proxy.has_method("note_predicted_damage") and proxy.get("enemy_stats") != null:
		predicted_hp = int(proxy.call("note_predicted_damage", predicted_damage))
	else:
		predicted_hp = maxi(1, int(enemy.get_meta("predicted_hp", int(stats.hp))) - predicted_damage)
		enemy.set_meta("predicted_hp", predicted_hp)
		stats.set("hp", predicted_hp)
	if bool(enemy.get_meta("network_test_target", false)):
		return
	if predicted_hp > 0:
		return
	enemy.set_meta("predicted_dead", true)
	if enemy.has_method("play_network_death"):
		return
	var icon: String = str(enemy.icon) if enemy.get("icon") != null else ""
	if icon != "":
		_play_enemy_death(icon, enemy.global_position)
	if enemy.has_method("idle_state"):
		enemy.call("idle_state")
	else:
		enemy.visible = false


func _freq_mult(freq: int) -> int:
	return SettingsScript.freq_mult(freq)


# 其它玩家来源特效：按 category 全局最短间隔（×1=不限，随档位降低而稀疏，0=关）。
func remote_effect_allowed(category: StringName) -> bool:
	var mult: int = _freq_mult(settings.remote_effect_freq)
	if mult <= 0:
		return false
	var interval: int = REMOTE_EFFECT_BASE_MS * (mult - 1)
	if interval <= 0:
		return true
	var key: String = str(category)
	var now: int = Time.get_ticks_msec()
	if now - int(_remote_fx_last_ms.get(key, -1000000000)) < interval:
		return false
	_remote_fx_last_ms[key] = now
	return true


# 其它玩家来源闪白：按实体最短间隔。
func remote_flash_allowed(body: Node) -> bool:
	var mult: int = _freq_mult(settings.remote_flash_freq)
	if mult <= 0:
		return false
	if body == null or not is_instance_valid(body):
		return true
	var interval: int = REMOTE_FLASH_BASE_MS * (mult - 1)
	if interval <= 0:
		return true
	var key: int = body.get_instance_id()
	var now: int = Time.get_ticks_msec()
	if now - int(_remote_flash_last_ms.get(key, -1000000000)) < interval:
		return false
	_remote_flash_last_ms[key] = now
	return true


# 其它玩家来源飘字：按 skip 节流（0=关 / 1=不节流 / N=每 N 次一飘）。
func _remote_text_should_emit() -> bool:
	var skip: int = _freq_mult(settings.remote_text_freq)
	if skip <= 0:
		return false
	if skip <= 1:
		return true
	_remote_text_counter += 1
	if _remote_text_counter >= skip:
		_remote_text_counter = 0
		return true
	return false


# ---------------- Boss 回合 / 专属事件 ----------------

func _on_boss_round_start() -> void:
	if is_lan_game and multiplayer.is_server():
		rpc("_remote_boss_round_start")


func _on_boss_round_end() -> void:
	if is_lan_game and multiplayer.is_server():
		rpc("_remote_boss_round_end")


@rpc("authority", "call_remote", "reliable")
func _remote_boss_round_start() -> void:
	if multiplayer.is_server():
		return
	GameEvents.emit_boss_round_start()


@rpc("authority", "call_remote", "reliable")
func _remote_boss_round_end() -> void:
	if multiplayer.is_server():
		return
	GameEvents.emit_boss_round_end()


# 通用 Boss 专属模式事件通道：Boss 脚本可调 CoopNet.instance.broadcast_boss_pattern_event(net_id, data)
func broadcast_boss_pattern_event(net_id: int, event_data: Dictionary) -> void:
	if not is_lan_game:
		return
	if multiplayer.is_server():
		rpc("_remote_boss_pattern_event", net_id, event_data)
	else:
		rpc_id(1, "_server_boss_pattern_event", net_id, event_data)


@rpc("any_peer", "call_remote", "reliable")
func _server_boss_pattern_event(net_id: int, event_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	for peer in multiplayer.get_peers():
		if peer != sender:
			rpc_id(peer, "_remote_boss_pattern_event", net_id, event_data)


@rpc("authority", "call_remote", "reliable")
func _remote_boss_pattern_event(net_id: int, event_data: Dictionary) -> void:
	boss_pattern_event_received.emit(net_id, event_data)


# 本体 Boss 通过 GameEvents.emit_boss_event 发出的事件 → host 广播 → client 重发
func _on_local_boss_event(event_name: String, data: Dictionary) -> void:
	if not is_lan_game or not multiplayer.is_server():
		return
	rpc("_remote_boss_event", event_name, data)


@rpc("authority", "call_remote", "reliable")
func _remote_boss_event(event_name: String, data: Dictionary) -> void:
	if multiplayer.is_server():
		return
	boss_events_received += 1
	GameEvents.emit_boss_event(event_name, data)


# ---------------- 联机流程入口（角色选择 / 测试房） ----------------

func request_character_select() -> void:
	if not is_lan_game:
		return
	if multiplayer.is_server():
		rpc("_remote_character_select")
	character_select_requested.emit()


@rpc("authority", "call_remote", "reliable")
func _remote_character_select() -> void:
	character_select_requested.emit()


func start_test_room() -> void:
	var scene: String = local_player_scene_path
	if scene == "":
		scene = "res://scenes/player/momoi/momoi.tscn"
	GameEvents.change_scene("res://scenes/main/test_room.tscn", scene)


# ---------------- 准备房流程（测试房 = 准备房） ----------------

# host：开房成功后自动进入准备房（测试房），等待其它玩家。绕过选人握手。
func enter_lobby() -> void:
	if not is_lan_game or not multiplayer.is_server():
		return
	if current_scene_path.contains("test_room"):
		return
	print("[etn_coop] enter lobby")
	_reset_run_state()
	_flow_phase = FlowPhase.LOBBY
	var local_id: int = multiplayer.get_unique_id()
	var host_scene: String = local_player_scene_path if local_player_scene_path != "" else DEFAULT_PLAYER_SCENE
	player_scene_by_peer.clear()
	selected_player_scene_by_peer.clear()
	player_scene_by_peer[local_id] = host_scene
	selected_player_scene_by_peer[local_id] = host_scene
	for p in multiplayer.get_peers():
		var pid: int = int(p)
		player_scene_by_peer[pid] = DEFAULT_PLAYER_SCENE
		selected_player_scene_by_peer[pid] = DEFAULT_PLAYER_SCENE
	_force_release = true
	_pending_scene_path = LOBBY_SCENE
	if not multiplayer.get_peers().is_empty():
		rpc("_remote_change_scene", LOBBY_SCENE, player_scene_by_peer, {})
	GameEvents.change_scene(LOBBY_SCENE, host_scene)


# host：开始球交互后广播进入选人阶段
func request_begin_select() -> void:
	if not is_lan_game or not multiplayer.is_server():
		return
	print("[etn_coop] begin character select")
	_flow_phase = FlowPhase.SELECT
	_select_flow_active = true
	select_ready_by_peer.clear()
	_clear_lobby_ready()
	_set_select_pause(true)
	rpc("_remote_select_begin")
	select_begin.emit()


@rpc("authority", "call_remote", "reliable")
func _remote_select_begin() -> void:
	if multiplayer.is_server():
		return
	_flow_phase = FlowPhase.SELECT
	_select_flow_active = true
	select_ready_by_peer.clear()
	lobby_ready_by_peer.clear()
	_refresh_all_ready_tags()
	_set_select_pause(true)
	select_begin.emit()


# 本机在选人界面确认角色：记录并上报 host
func report_local_selection(scene_path: String) -> void:
	if not is_lan_game or scene_path == "":
		return
	local_player_scene_path = scene_path
	var pid: int = multiplayer.get_unique_id()
	selected_player_scene_by_peer[pid] = scene_path
	if not multiplayer.is_server():
		rpc_id(1, "_server_player_selected", scene_path)


# 本机就绪 / 取消就绪（选人阶段）
func report_select_ready(ready: bool) -> void:
	if not is_lan_game:
		return
	if multiplayer.is_server():
		_set_select_ready(multiplayer.get_unique_id(), ready)
	else:
		rpc_id(1, "_server_select_ready", ready)


@rpc("any_peer", "call_remote", "reliable")
func _server_select_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	_set_select_ready(multiplayer.get_remote_sender_id(), ready)


func _set_select_ready(pid: int, ready: bool) -> void:
	if ready:
		select_ready_by_peer[pid] = true
	else:
		select_ready_by_peer.erase(pid)
	rpc("_remote_select_ready_changed", pid, ready)
	select_ready_changed.emit(pid, ready)
	if multiplayer.is_server():
		_maybe_finish_select()


@rpc("authority", "call_remote", "reliable")
func _remote_select_ready_changed(pid: int, ready: bool) -> void:
	if multiplayer.is_server():
		return
	select_ready_changed.emit(pid, ready)


# host：全员就绪 → 广播进入 ALL_READY（非 host 显示"等待房主选择"）
func _maybe_finish_select() -> void:
	if not multiplayer.is_server():
		return
	if _flow_phase != FlowPhase.SELECT:
		return
	var expected: Array = [multiplayer.get_unique_id()]
	for p in multiplayer.get_peers():
		expected.append(int(p))
	for p in expected:
		if not select_ready_by_peer.has(int(p)):
			return
	print("[etn_coop] all players ready")
	_flow_phase = FlowPhase.ALL_READY
	rpc("_remote_select_all_ready")
	select_all_ready.emit()


@rpc("authority", "call_remote", "reliable")
func _remote_select_all_ready() -> void:
	if multiplayer.is_server():
		return
	if _flow_phase == FlowPhase.SELECT:
		_flow_phase = FlowPhase.ALL_READY
	select_all_ready.emit()


# host：从难度面板取消 → 全员取消就绪，回到选人界面
func cancel_select() -> void:
	if not is_lan_game or not multiplayer.is_server():
		return
	print("[etn_coop] host cancelled difficulty; reset ready")
	_flow_phase = FlowPhase.SELECT
	_select_flow_active = true
	select_ready_by_peer.clear()
	rpc("_remote_select_cancelled")
	select_cancelled.emit()


@rpc("authority", "call_remote", "reliable")
func _remote_select_cancelled() -> void:
	if multiplayer.is_server():
		return
	_flow_phase = FlowPhase.SELECT
	_select_flow_active = true
	select_ready_by_peer.clear()
	select_cancelled.emit()


# host：直接开战（开发自测/程序化入口）。UI 难度按钮走 change_scene gate 的 ALL_READY 分支。
func begin_battle(scene_path: String = "") -> void:
	if not is_lan_game or not multiplayer.is_server():
		return
	if scene_path == "":
		scene_path = DEFAULT_BATTLE_SCENE
	_select_flow_active = false
	_flow_phase = FlowPhase.BATTLE
	select_ready_by_peer.clear()
	lobby_ready_by_peer.clear()
	_set_select_pause(false)
	_pending_scene_path = scene_path
	var local_id: int = multiplayer.get_unique_id()
	if local_player_scene_path != "":
		selected_player_scene_by_peer[local_id] = local_player_scene_path
	_broadcast_roster()
	_force_release = true
	GameEvents.change_scene(scene_path, local_player_scene_path)


# ---------------- 选人阶段全局暂停 ----------------

func _set_select_pause(on: bool) -> void:
	if get_tree() != null:
		get_tree().paused = on


func is_all_ready() -> bool:
	return _flow_phase == FlowPhase.ALL_READY


# host：取消整轮选人，全员回准备房并解除暂停
func abort_select_to_lobby() -> void:
	if not is_lan_game or not multiplayer.is_server():
		return
	print("[etn_coop] host aborted selection; back to lobby")
	_flow_phase = FlowPhase.LOBBY
	_select_flow_active = false
	select_ready_by_peer.clear()
	lobby_ready_by_peer.clear()
	_refresh_all_ready_tags()
	var local_id: int = multiplayer.get_unique_id()
	var host_scene: String = local_player_scene_path if local_player_scene_path != "" else DEFAULT_PLAYER_SCENE
	selected_player_scene_by_peer.clear()
	player_scene_by_peer.clear()
	player_scene_by_peer[local_id] = host_scene
	selected_player_scene_by_peer[local_id] = host_scene
	for p in multiplayer.get_peers():
		var pid: int = int(p)
		player_scene_by_peer[pid] = DEFAULT_PLAYER_SCENE
		selected_player_scene_by_peer[pid] = DEFAULT_PLAYER_SCENE
	_set_select_pause(false)
	rpc("_remote_abort_select_to_lobby", player_scene_by_peer)
	select_aborted.emit()


@rpc("authority", "call_remote", "reliable")
func _remote_abort_select_to_lobby(roster: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_flow_phase = FlowPhase.LOBBY
	_select_flow_active = false
	select_ready_by_peer.clear()
	lobby_ready_by_peer.clear()
	_refresh_all_ready_tags()
	if roster != null and not roster.is_empty():
		player_scene_by_peer = roster.duplicate()
	_set_select_pause(false)
	select_aborted.emit()


# ---------------- 大厅「已准备」（开始球） ----------------

# 非房主：切换自己的准备状态（本地乐观 + 上报 host 转发）
func toggle_local_ready() -> void:
	if not is_lan_game:
		return
	var pid: int = multiplayer.get_unique_id()
	var value: bool = not bool(lobby_ready_by_peer.get(pid, false))
	_apply_lobby_ready(pid, value)
	if multiplayer.is_server():
		rpc("_remote_lobby_ready", pid, value)
	else:
		rpc_id(1, "_server_lobby_ready", value)


@rpc("any_peer", "call_remote", "reliable")
func _server_lobby_ready(value: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_apply_lobby_ready(sender, value)
	rpc("_remote_lobby_ready", sender, value)


@rpc("authority", "call_remote", "reliable")
func _remote_lobby_ready(pid: int, value: bool) -> void:
	_apply_lobby_ready(pid, value)


func _apply_lobby_ready(pid: int, value: bool) -> void:
	if bool(lobby_ready_by_peer.get(pid, false)) == value:
		return
	if value:
		lobby_ready_by_peer[pid] = true
	else:
		lobby_ready_by_peer.erase(pid)
	_set_player_ready_tag(pid, value)


# host：所有非房主玩家都已准备（无客机时为 true）
func are_all_players_ready() -> bool:
	if not multiplayer.is_server():
		return false
	for p in multiplayer.get_peers():
		if not bool(lobby_ready_by_peer.get(int(p), false)):
			return false
	return true


# 进入选人时清空并隐藏所有人的「已准备」
func _clear_lobby_ready() -> void:
	lobby_ready_by_peer.clear()
	_refresh_all_ready_tags()
	rpc("_remote_lobby_ready_clear")


@rpc("authority", "call_remote", "reliable")
func _remote_lobby_ready_clear() -> void:
	lobby_ready_by_peer.clear()
	_refresh_all_ready_tags()


func _set_player_ready_tag(pid: int, value: bool) -> void:
	var p: Node = _local_or_remote_player(pid)
	if p == null or not is_instance_valid(p):
		return
	var tag = p.get_node_or_null("CoopNameTag")
	if tag != null and tag.has_method("set_ready"):
		tag.call("set_ready", value)


func _refresh_all_ready_tags() -> void:
	var local_id: int = multiplayer.get_unique_id()
	_set_player_ready_tag(local_id, bool(lobby_ready_by_peer.get(local_id, false)))
	for pid in player_by_peer_id.keys():
		_set_player_ready_tag(int(pid), bool(lobby_ready_by_peer.get(int(pid), false)))


# ---------------- 房间标识（右上角显示用） ----------------

func get_room_display_text() -> String:
	if not is_lan_game:
		return ""
	if is_relay:
		if relay_room_code != "":
			return tr("coop_room_number") + " " + relay_room_code
		return tr("coop_room_number") + " ..."
	return tr("coop_room_ip") + " " + _local_ipv4_text() + ":" + str(DEFAULT_PORT)


func _local_ipv4_text() -> String:
	for address in IP.get_local_addresses():
		if address.contains(":"):
			continue
		if address == "127.0.0.1" or address == "0.0.0.0":
			continue
		if address.begins_with("169.254."):
			continue
		return address
	return "127.0.0.1"


# ---------------- 关卡目录（数据驱动，便于 Mod 扩展） ----------------

const _BASE_LEVELS: Array[String] = [
	"res://resources/level/normal.tres",
	"res://resources/level/hard.tres",
	"res://resources/level/extreme.tres",
	"res://resources/level/insane.tres",
]


func get_level_catalog() -> Array:
	if not _level_catalog_built:
		_build_level_catalog()
	return _level_catalog


func register_level(id: String, display_name: String, level_resource, scene_path: String) -> void:
	if not _level_catalog_built:
		_build_level_catalog()
	for entry in _level_catalog:
		if str(entry.get("id", "")) == id:
			entry["name"] = display_name
			entry["level"] = level_resource
			entry["scene_path"] = scene_path
			return
	_level_catalog.append({"id": id, "name": display_name, "level": level_resource, "scene_path": scene_path})


func _build_level_catalog() -> void:
	_level_catalog_built = true
	_level_catalog.clear()
	for path in _BASE_LEVELS:
		var lv = load(path)
		if lv == null:
			continue
		var scene: String = DEFAULT_BATTLE_SCENE
		var custom = lv.get("level_scene_path")
		if custom is String and custom != "":
			scene = custom
		_level_catalog.append({"id": str(lv.level_id), "name": str(lv.level_name), "level": lv, "scene_path": scene})
	for lv in ModManager.get_content("levels"):
		if lv == null:
			continue
		var scene2: String = DEFAULT_BATTLE_SCENE
		var custom2 = lv.get("level_scene_path")
		if custom2 is String and custom2 != "":
			scene2 = custom2
		_level_catalog.append({"id": str(lv.level_id), "name": str(lv.level_name), "level": lv, "scene_path": scene2})


# ---------------- 连接管理 ----------------

func host_game(port: int = DEFAULT_PORT) -> bool:
	close_connection()
	transport = TransportScript.create_lan_host(port, MAX_PLAYERS)
	if transport == null or transport.peer == null:
		var msg: String = transport.status_message if transport != null else "null transport"
		push_warning("[etn_coop] host failed: %s" % msg)
		return false
	multiplayer.multiplayer_peer = transport.peer
	is_lan_game = true
	print("[etn_coop] hosting LAN on port %d" % port)
	connection_status_changed.emit("Hosting LAN on port %d" % port)
	if auto_enter_lobby:
		enter_lobby()
	return true


func join_game(ip: String, port: int = DEFAULT_PORT) -> bool:
	close_connection()
	transport = TransportScript.create_lan_client(ip, port)
	if transport == null or transport.peer == null:
		var msg: String = transport.status_message if transport != null else "null transport"
		push_warning("[etn_coop] join failed: %s" % msg)
		connection_status_changed.emit("Join failed: %s" % msg)
		return false
	multiplayer.multiplayer_peer = transport.peer
	is_lan_game = true
	print("[etn_coop] joining %s:%d" % [ip, port])
	connection_status_changed.emit("Joining %s:%d" % [ip, port])
	return true


func create_relay_room(server_url: String) -> String:
	close_connection()
	transport = TransportScript.create_relay(server_url, "", "host")
	if transport == null or transport.peer == null:
		var msg: String = transport.status_message if transport != null else "null transport"
		push_warning("[etn_coop] relay create failed: %s" % msg)
		connection_status_changed.emit("Relay failed: %s" % msg)
		return ""
	is_relay = true
	relay_server_url = server_url
	multiplayer.multiplayer_peer = transport.peer
	is_lan_game = true
	var relay_peer = transport.peer
	if relay_peer.has_signal("relay_room_created"):
		relay_peer.relay_room_created.connect(_on_relay_room_created)
	if relay_peer.has_signal("relay_error"):
		relay_peer.relay_error.connect(_on_relay_error)
	print("[etn_coop] relay room creating on %s" % server_url)
	connection_status_changed.emit("Creating relay room")
	return "PENDING"


func join_relay_room(server_url: String, room_code: String) -> bool:
	close_connection()
	transport = TransportScript.create_relay(server_url, room_code, "client")
	if transport == null or transport.peer == null:
		var msg: String = transport.status_message if transport != null else "null transport"
		push_warning("[etn_coop] relay join failed: %s" % msg)
		connection_status_changed.emit("Relay failed: %s" % msg)
		return false
	is_relay = true
	relay_server_url = server_url
	relay_room_code = room_code
	multiplayer.multiplayer_peer = transport.peer
	is_lan_game = true
	var relay_peer = transport.peer
	if relay_peer.has_signal("relay_room_joined"):
		relay_peer.relay_room_joined.connect(_on_relay_room_joined)
	if relay_peer.has_signal("relay_error"):
		relay_peer.relay_error.connect(_on_relay_error)
	print("[etn_coop] relay join %s @ %s" % [room_code, server_url])
	connection_status_changed.emit("Joining relay room %s" % room_code)
	return true


func _on_relay_room_created(code: String) -> void:
	relay_room_code = code
	print("[etn_coop] RELAY_ROOM_CODE=%s" % code)
	connection_status_changed.emit("Relay room %s created" % code)
	relay_room_created.emit(code)
	if auto_enter_lobby:
		enter_lobby()


func _on_relay_room_joined(peer_id: int) -> void:
	connection_status_changed.emit("Joined relay as peer %d" % peer_id)


func _on_relay_error(message: String) -> void:
	push_warning("[etn_coop] relay error: %s" % message)
	connection_status_changed.emit("Relay failed: %s" % message)


func close_connection(silent: bool = false) -> void:
	if transport != null and transport.peer != null:
		transport.peer.close()
	transport = null
	multiplayer.multiplayer_peer = null
	is_lan_game = false
	is_relay = false
	relay_room_code = ""
	if _discovery != null:
		_discovery.call("advertise_stop")
	_reset_run_state()
	if not silent:
		connection_status_changed.emit("offline")


# ---------------- 网络诊断（HUD 用，对齐联机版） ----------------

func set_network_diag_enabled(on: bool) -> void:
	net_diag_enabled = on
	if on:
		return
	_diag_pending.clear()
	# 保留 _latency_samples/_delivery_samples：RTT/抖动常开，供自适应插值延迟使用
	_diag_elapsed = 0.0
	_rate_window_msec = 0
	_rate_last_bullet_sent = net_bullet_sent
	_rate_last_bullet_recv = net_bullet_recv
	_rate_last_effect_sent = net_effect_sent
	_rate_last_effect_recv = net_effect_recv


func _update_network_diagnostics(delta: float) -> void:
	# RTT/抖动常开（供自适应插值延迟）；HUD 仅控制显示与速率统计
	if not is_lan_game:
		return
	if multiplayer.multiplayer_peer == null:
		return
	var now: int = Time.get_ticks_msec()
	if not _diag_pending.is_empty():
		for k in _diag_pending.keys():
			if now - int(_diag_pending[k]) > NET_DIAG_TIMEOUT_MSEC:
				_diag_pending.erase(k)
				_delivery_samples.append(0.0)
				_trim_net_samples()
	_diag_elapsed += delta
	if _diag_elapsed < NET_DIAG_INTERVAL:
		return
	_diag_elapsed = 0.0
	_diag_seq += 1
	_diag_pending[_diag_seq] = now
	if multiplayer.is_server():
		rpc("_diag_ping", _diag_seq)
	else:
		rpc_id(1, "_diag_ping", _diag_seq)
	net_rtt_ms = _sample_avg(_latency_samples)
	net_jitter_ms = _sample_jitter()
	if not (net_diag_enabled or sim_report_enabled):
		return
	# 速率：窗口内发送/接收计数除以实际窗口时长
	if _rate_window_msec > 0:
		var dt: float = maxf(0.001, float(now - _rate_window_msec) / 1000.0)
		_rate_bullet_sent = float(net_bullet_sent - _rate_last_bullet_sent) / dt
		_rate_bullet_recv = float(net_bullet_recv - _rate_last_bullet_recv) / dt
		_rate_effect_sent = float(net_effect_sent - _rate_last_effect_sent) / dt
		_rate_effect_recv = float(net_effect_recv - _rate_last_effect_recv) / dt
	_rate_last_bullet_sent = net_bullet_sent
	_rate_last_bullet_recv = net_bullet_recv
	_rate_last_effect_sent = net_effect_sent
	_rate_last_effect_recv = net_effect_recv
	_rate_window_msec = now


@rpc("any_peer", "call_remote", "unreliable")
func _diag_ping(seq: int) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	rpc_id(sender, "_diag_pong", seq)


@rpc("any_peer", "call_remote", "unreliable")
func _diag_pong(seq: int) -> void:
	if not _diag_pending.has(seq):
		return
	var sent: int = int(_diag_pending[seq])
	_diag_pending.erase(seq)
	_latency_samples.append(float(Time.get_ticks_msec() - sent))
	_delivery_samples.append(1.0)
	_trim_net_samples()


func _trim_net_samples() -> void:
	while _latency_samples.size() > NET_DIAG_SAMPLE_LIMIT:
		_latency_samples.remove_at(0)
	while _delivery_samples.size() > NET_DIAG_SAMPLE_LIMIT:
		_delivery_samples.remove_at(0)


func _sample_avg(samples: Array) -> float:
	if samples.is_empty():
		return 0.0
	var total: float = 0.0
	for v in samples:
		total += float(v)
	return total / float(samples.size())


func _sample_loss() -> float:
	if _delivery_samples.is_empty():
		return 0.0
	var lost: int = 0
	for v in _delivery_samples:
		if float(v) <= 0.0:
			lost += 1
	return 100.0 * float(lost) / float(_delivery_samples.size())


# 供远端 proxy 计算自适应插值延迟：rtt/jitter（毫秒）
func get_network_timing() -> Dictionary:
	return {"rtt": _sample_avg(_latency_samples), "jitter": _sample_jitter()}


func _sample_jitter() -> float:
	if _latency_samples.size() < 2:
		return 0.0
	var mean: float = _sample_avg(_latency_samples)
	var total: float = 0.0
	for v in _latency_samples:
		total += absf(float(v) - mean)
	return total / float(_latency_samples.size())


func get_network_debug_text() -> String:
	if not is_lan_game:
		return "coop: off"
	var role: String = "host" if multiplayer.is_server() else "client"
	var lines: Array[String] = []
	lines.append("coop %s  id=%d  peers=%d" % [role, multiplayer.get_unique_id(), multiplayer.get_peers().size()])
	lines.append("rtt=%.0fms  jitter=%.0fms  loss=%.0f%%" % [_sample_avg(_latency_samples), _sample_jitter(), _sample_loss()])
	lines.append("comp  extrap=%d  snap=%d  sim(lat=%.0f jit=%.0f loss=%.0f)" % [net_extrap_events, net_hard_snaps, sim_latency_ms, sim_jitter_ms, sim_loss_pct])
	lines.append("hit  ok=%d  reject=%d" % [net_hits_accepted, net_hits_rejected])
	lines.append("bullet  tx=%.1f/s rx=%.1f/s" % [_rate_bullet_sent, _rate_bullet_recv])
	lines.append("effect  tx=%.1f/s rx=%.1f/s" % [_rate_effect_sent, _rate_effect_recv])
	var p := get_local_player()
	if p != null and is_instance_valid(p) and p.get("stats") != null:
		lines.append("pos=(%.0f, %.0f)  hp=%d" % [p.global_position.x, p.global_position.y, int(p.stats.hp)])
	return "\n".join(lines)


func get_network_quality_debug_text() -> String:
	var rtt: float = _sample_avg(_latency_samples)
	var loss: float = _sample_loss()
	if rtt < 60.0 and loss < 2.0:
		return "good"
	if rtt < 140.0 and loss < 8.0:
		return "fair"
	return "poor"


func get_local_player() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	# 优先按 peer_id meta 在 PlayerRoot 中判定（对齐联机版），回退 "Player" 组
	var root := tree.get_first_node_in_group("PlayerRoot")
	if root != null:
		var local_id: int = multiplayer.get_unique_id()
		for child in root.get_children():
			if child.has_meta("peer_id") and int(child.get_meta("peer_id")) == local_id:
				return child
	return tree.get_first_node_in_group("Player")


# ---------------- 骨架调试热键 ----------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_F10:
			host_game()
		KEY_F11:
			join_game("127.0.0.1")
		KEY_F12:
			close_connection()
			print("[etn_coop] connection closed")
