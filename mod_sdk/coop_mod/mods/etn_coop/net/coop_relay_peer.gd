extends MultiplayerPeerExtension

## CoopRelayPeer：WebSocket 中继 MultiplayerPeer（移植自 coop 实现）。
## 依赖外部中继服务端（协议：create_room/join_room → room_created/join_prepared/join_admitted/peer_*）。
## mod 内不使用 class_name。

signal relay_room_created(room_code: String)
signal relay_room_joined(peer_id: int)
signal relay_error(message: String)
# 服务端声明的带宽预算（建/入房时下发；老服务端不发则保持 0）
signal relay_link_budget_changed(egress_kib: float, mbps: float)
# 服务端软水位劝降：level 1=轻度、2=重度，ttl_ms 后自动恢复
signal relay_shed(level: int, ttl_ms: int)
# 服务端告知「某个客机拥塞」：host 据此对该 peer 停发视觉（状态/事件照发）
signal relay_peer_congested(peer_id: int, level: int)

const JOIN_HANDSHAKE_TIMEOUT_MSEC: int = 30000
const CONNECT_TIMEOUT_MSEC: int = 30000
# 版本上报：随 create_room/join_room 一起发给中继服务端，服务端写进 [STATS]/[BACKPRESSURE] 等日志，
# 用于「按 mod 版本聚合带宽与踢人率」。由 coop_net._ready() 写入（- 表示老客户端/未设置）。
static var client_ver: String = "-"
static var client_proto: int = 0
# 服务端声明的公网带宽预算（KiB/s 与 Mbps）。0 = 未声明（老服务端），由 coop_net 用兜底值。
var link_egress_kib: float = 0.0
var link_mbps: float = 0.0
# 背压：每帧最多从 WS 取这么多帧，剩余留在 WS 内部缓冲下一帧再取。
# 服务端对慢端不丢帧（软水位 256KB / 宽限 5s），客户端一卡就是几百帧积压；
# 若在一帧内全部消化，会产生该帧 CPU 尖峰 + 多个快照同帧压入插值缓冲（表现=卡一下然后瞬移）。
const MAX_WS_PACKETS_PER_POLL: int = 256
# 待交给 SceneMultiplayer 的队列上限。超限丢**最旧**、保最新（最新状态才有价值）。
const MAX_QUEUED_PACKETS: int = 2048
const MAX_QUEUED_BYTES: int = 16 * 1024 * 1024
# 连续发送失败达到该次数即判定中继链路已坏：WS 出缓冲满时 send() 会直接失败，
# 而引擎不会重试 → 可靠 RPC 静默丢失 → 两端状态永久分叉。宁可不丢不报，也不能静默。
const MAX_SEND_FAILS: int = 32

var _ws := WebSocketPeer.new()
var _unique_id: int = 0
var _status: MultiplayerPeer.ConnectionStatus = MultiplayerPeer.CONNECTION_DISCONNECTED
var _target_peer: int = 0
var _transfer_mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _transfer_channel: int = 0
var _refuse_connections: bool = false
var _incoming: Array[Dictionary] = []
var _incoming_bytes: int = 0
var _current_pkt_peer: int = 0
var _current_pkt_channel: int = 0
var _current_pkt_mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _peers_to_connect: Array[int] = []
var _peers_to_disconnect: Array[int] = []
var _pending_peers: Array[int] = []
var _known_peers: Dictionary = {}
var _join_handshake_started_msec: int = 0
var _connect_started_msec: int = 0
var _pending_action: String = ""
var _pending_name: String = ""
var _pending_room_code: String = ""
var _pending_token: String = ""
var _action_sent: bool = false
var _admitted: Dictionary = {}          # peer_id -> true（已 emit 过 peer_connected，防重复接入）
var _relay_debug: bool = OS.is_debug_build()
# 发送失败诊断：WebSocket 出缓冲满等导致 send() 失败时计数（不再静默当作成功）
var send_fail_count: int = 0
var _send_fail_warn_msec: int = 0
var _send_fail_streak: int = 0
# 收发字节累计（诊断：算客户端侧的实际带宽 KB/s）。
var tx_bytes: int = 0
var rx_bytes: int = 0
# 队列溢出丢弃计数（只作诊断，不参与逻辑）；backlog_peak 供上层判断落后程度峰值。
var _overload_dropped: int = 0
var _overload_warn_msec: int = 0
var backlog_peak: int = 0
# 最近一次弹出帧的入队时刻（msec）；仅诊断用。
var _current_arrival_msec: int = 0


# 排入待接入列表（去重 + 跳过自身/0）。真正 emit 在 _poll 末尾统一做。
func _queue_peer(peer_id: int) -> void:
	if peer_id <= 0 or peer_id == _unique_id:
		return
	if _admitted.has(peer_id) or _peers_to_connect.has(peer_id):
		return
	_peers_to_connect.append(peer_id)


func create_relay_host(url: String, player_name: String, token: String = "") -> Error:
	_pending_action = "create"
	_pending_name = player_name
	_pending_token = token
	_action_sent = false
	_connect_started_msec = Time.get_ticks_msec()
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	var error := _ws.connect_to_url(url)
	if error != OK:
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		_connect_started_msec = 0
	return error


func join_relay_room(url: String, room_code: String, player_name: String, token: String = "") -> Error:
	_pending_action = "join"
	_pending_name = player_name
	_pending_room_code = room_code
	_pending_token = token
	_action_sent = false
	_connect_started_msec = Time.get_ticks_msec()
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	var error := _ws.connect_to_url(url)
	if error != OK:
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		_connect_started_msec = 0
	return error


func _poll() -> void:
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CLOSED:
			if _status != MultiplayerPeer.CONNECTION_DISCONNECTED:
				var was_connecting: bool = _status == MultiplayerPeer.CONNECTION_CONNECTING
				_status = MultiplayerPeer.CONNECTION_DISCONNECTED
				_connect_started_msec = 0
				if was_connecting:
					relay_error.emit("Relay connection failed")
			return
		WebSocketPeer.STATE_CONNECTING:
			if _connect_started_msec > 0 and Time.get_ticks_msec() - _connect_started_msec > CONNECT_TIMEOUT_MSEC:
				_connect_started_msec = 0
				_status = MultiplayerPeer.CONNECTION_DISCONNECTED
				relay_error.emit("Relay connection timed out")
				_ws.close()
			return
		WebSocketPeer.STATE_OPEN:
			_connect_started_msec = 0

	if _join_handshake_started_msec > 0 and _status == MultiplayerPeer.CONNECTION_CONNECTING:
		if Time.get_ticks_msec() - _join_handshake_started_msec > JOIN_HANDSHAKE_TIMEOUT_MSEC:
			_join_handshake_started_msec = 0
			_status = MultiplayerPeer.CONNECTION_DISCONNECTED
			relay_error.emit("Relay join timed out")
			_ws.close()
			return

	if not _action_sent and _pending_action != "":
		_action_sent = true
		# 发送建/入房控制帧即起算握手超时：覆盖「WS 已 open 但首个控制回复迟迟不来」的缺口
		_join_handshake_started_msec = Time.get_ticks_msec()
		if _pending_action == "create":
			_ws.send_text(JSON.stringify({
				"type": "create_room",
				"player_name": _pending_name,
				"token": _pending_token,
				"ver": client_ver,
				"proto": client_proto,
			}))
		elif _pending_action == "join":
			_ws.send_text(JSON.stringify({
				"type": "join_room",
				"room_code": _pending_room_code,
				"player_name": _pending_name,
				"token": _pending_token,
				"ver": client_ver,
				"proto": client_proto,
			}))
		_pending_action = ""

	# 分帧取包：把积压摊到多帧，避免"恢复那一帧一次性消化几百帧"的尖峰。
	var packets_processed: int = 0
	while _ws.get_available_packet_count() > 0 and packets_processed < MAX_WS_PACKETS_PER_POLL:
		var packet := _ws.get_packet()
		packets_processed += 1
		if _ws.was_string_packet():
			_on_control(packet.get_string_from_utf8())
		else:
			_on_data(packet)

	var now_backlog: int = backlog_count()
	if now_backlog > backlog_peak:
		backlog_peak = now_backlog

	_flush_peer_events()


func _flush_peer_events() -> void:
	# 同一次 poll 可包含旧连接断开及同 ID 重连：先移除旧身份，再接入新身份。
	for peer_id in _peers_to_disconnect:
		emit_signal("peer_disconnected", peer_id)
	_peers_to_disconnect.clear()
	for peer_id in _peers_to_connect:
		if not _admitted.has(peer_id):
			_admitted[peer_id] = true
			if _relay_debug:
				print("[etn_coop][relay] admit peer=%d" % peer_id)
			emit_signal("peer_connected", peer_id)
	_peers_to_connect.clear()

# 服务端带宽预算（KiB/s 与 Mbps）：只声明一次，变化时发信号。老服务端不带字段 → 保持 0。
func _read_link_budget(data: Dictionary) -> void:
	var egress := float(data.get("egress_kib", 0.0))
	if egress <= 0.0:
		return
	var mbps := float(data.get("link_mbps", 0.0))
	if is_equal_approx(egress, link_egress_kib) and is_equal_approx(mbps, link_mbps):
		return
	link_egress_kib = egress
	link_mbps = mbps
	relay_link_budget_changed.emit(egress, mbps)


func _on_control(text: String) -> void:
	var data = JSON.parse_string(text)
	if not (data is Dictionary):
		return
	if _relay_debug:
		print("[etn_coop][relay] <- %s" % text)
	# 服务端带宽预算可能挂在 room_created / join_prepared / join_admitted 任意一条上，统一读取
	_read_link_budget(data)
	match data.get("type", ""):
		"room_created":
			_unique_id = int(data.get("peer_id", 1))
			_known_peers[_unique_id] = "self"
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			_join_handshake_started_msec = 0
			relay_room_created.emit(str(data.get("room_code", "")))
		"shed":
			# 服务端软水位劝降：level 1=轻度、2=重度；ttl 到期自动恢复。老客户端会忽略本分支。
			var shed_level: int = clampi(int(data.get("level", 1)), 0, 2)
			var shed_ttl: int = clampi(int(data.get("ttl_ms", 3000)), 0, 30000)
			relay_shed.emit(shed_level, shed_ttl)
		"peer_congested":
			var c_peer: int = int(data.get("peer", 0))
			var c_level: int = clampi(int(data.get("level", 0)), 0, 2)
			if c_peer > 0:
				relay_peer_congested.emit(c_peer, c_level)
		"join_prepared":
			_unique_id = int(data.get("peer_id", 0))
			_join_handshake_started_msec = Time.get_ticks_msec()
			_pending_peers.clear()
			var peers = data.get("peers", [])
			if not (peers is Array):
				peers = []
			for peer_info in peers:
				if not (peer_info is Dictionary):
					continue
				var peer_id := int(peer_info.get("peer_id", 0))
				if peer_id <= 0:
					continue
				_known_peers[peer_id] = peer_info.get("name", "")
				if peer_id != _unique_id:
					_pending_peers.append(peer_id)
			_send_control_json({"type": "client_ready"})
		"join_admitted":
			_join_handshake_started_msec = 0
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			# 协议保证 host=1、client>=2；客机必须接入 host 才会触发引擎 connected_to_server，
			# 否则不会发 _client_hello → 房主不 _accept_peer → 不进入准备房。服务端 peers 未含 host 时补上。
			if _unique_id != 1 and not _pending_peers.has(1):
				_pending_peers.append(1)
			if _unique_id != 1 and not _known_peers.has(1):
				_known_peers[1] = "host"
			for peer_id in _pending_peers:
				_queue_peer(int(peer_id))
			_pending_peers.clear()
			relay_room_joined.emit(_unique_id)
		"peer_pending":
			var pending_peer_id := int(data.get("peer_id", 0))
			if pending_peer_id != 0 and pending_peer_id != _unique_id:
				_known_peers[pending_peer_id] = str(data.get("name", ""))
				_queue_peer(pending_peer_id)
		"peer_connected":
			var connected_peer_id := int(data.get("peer_id", 0))
			_known_peers[connected_peer_id] = data.get("name", "")
			_queue_peer(connected_peer_id)
		"peer_disconnected":
			var disconnected_peer_id := int(data.get("peer_id", 0))
			_known_peers.erase(disconnected_peer_id)
			# SceneMultiplayer 会在 _poll 返回后才取包；不能先移除 sender 再交付旧包。
			_incoming = _incoming.filter(func(packet): return int(packet.peer) != disconnected_peer_id)
			# filter 重建了整表：字节记账必须重算，否则会一直偏大直至误触发上限。
			_incoming_bytes = 0
			for q in _incoming:
				_incoming_bytes += (q["data"] as PackedByteArray).size()
			_peers_to_connect.erase(disconnected_peer_id)
			if _admitted.has(disconnected_peer_id) and not _peers_to_disconnect.has(disconnected_peer_id):
				_peers_to_disconnect.append(disconnected_peer_id)
			_admitted.erase(disconnected_peer_id)
			if disconnected_peer_id == 1 and _unique_id != 1:
				_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		"error":
			relay_error.emit(str(data.get("message", "Relay error")))
			if _status == MultiplayerPeer.CONNECTION_CONNECTING:
				_status = MultiplayerPeer.CONNECTION_DISCONNECTED


func _send_control_json(message: Dictionary) -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ws.send_text(JSON.stringify(message))


func _on_data(packet: PackedByteArray) -> void:
	if packet.size() < 4:
		return
	rx_bytes += packet.size()
	var source := packet.decode_s32(0)
	# 服务端在允许转发前已发送 peer_pending/join_prepared。晚到的旧连接数据
	# 不能凭二进制包重新接入；同 ID 的新连接必须先有明确的控制帧。
	if not _known_peers.has(source):
		return
	_queue_peer(source)
	var payload := packet.slice(4)
	# 队列封顶：丢最旧、保最新。超限说明本机已严重落后，此时只有最新数据有意义；
	# 丢旧包而不是拒收新包，避免"越卡越只拿到旧状态"。不断链——中继上断链会走掉线重连流程，体感更差。
	var dropped_now: int = 0
	while not _incoming.is_empty() and (
			_incoming.size() >= MAX_QUEUED_PACKETS
			or _incoming_bytes + payload.size() > MAX_QUEUED_BYTES):
		var dropped_packet: Dictionary = _incoming.pop_front()
		_incoming_bytes = maxi(0, _incoming_bytes - (dropped_packet["data"] as PackedByteArray).size())
		_overload_dropped += 1
		dropped_now += 1
	if dropped_now > 0:
		var warn_now: int = Time.get_ticks_msec()
		if warn_now - _overload_warn_msec > 5000:
			_overload_warn_msec = warn_now
			push_warning("[etn_coop][relay] incoming queue overload dropped=%d backlog=%d" % [_overload_dropped, _incoming.size()])
	_incoming.append({
		"data": payload,
		"peer": source,
		"channel": 0,
		"mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE,
		"t": Time.get_ticks_msec(),
	})
	_incoming_bytes += payload.size()


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	var packet: Dictionary = _incoming.pop_front()
	var payload: PackedByteArray = packet["data"]
	_incoming_bytes = maxi(0, _incoming_bytes - payload.size())
	_current_arrival_msec = int(packet.get("t", 0))
	_current_pkt_peer = packet["peer"]
	_current_pkt_channel = packet["channel"]
	_current_pkt_mode = packet["mode"]
	return payload


func _get_packet_peer() -> int:
	# 引擎 SceneMultiplayer::poll() 先 get_packet_peer() 再 get_packet()（弹出），
	# 故这里必须返回「队首包」的 peer（peek），不能返回上次 pop 的值，否则 sender 错位一拍：
	# 首个包报 0、断线后报已断开 id → 引擎 !connected_peers.has(sender) 红字 / 多端错配。
	if _incoming.is_empty():
		return _current_pkt_peer
	return int(_incoming[0]["peer"])


func _get_packet_channel() -> int:
	if _incoming.is_empty():
		return _current_pkt_channel
	return int(_incoming[0]["channel"])


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	if _incoming.is_empty():
		return _current_pkt_mode
	return _incoming[0]["mode"]


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	var header := PackedByteArray()
	header.resize(4)
	header.encode_s32(0, _target_peer)
	var err := _ws.send(header + p_buffer)
	if err != OK:
		send_fail_count += 1
		_send_fail_streak += 1
		var now: int = Time.get_ticks_msec()
		if now - _send_fail_warn_msec > 5000:
			_send_fail_warn_msec = now
			push_warning("[etn_coop][relay] send failed err=%d total=%d streak=%d" % [err, send_fail_count, _send_fail_streak])
		# 连续失败 = 链路已坏：升级为会话错误交给上层重连，避免可靠 RPC 被静默吞掉。
		if _send_fail_streak >= MAX_SEND_FAILS:
			relay_error.emit("Relay send failed %d times in a row; reconnecting" % _send_fail_streak)
			_close()
	else:
		_send_fail_streak = 0
		tx_bytes += header.size() + p_buffer.size()
	return err


func _get_unique_id() -> int:
	return _unique_id


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


# 当前还有多少帧没被消费（本 peer 队列 + WS 内部缓冲）。供上层估计"落后程度"。
func backlog_count() -> int:
	var ws_pending: int = 0
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws_pending = _ws.get_available_packet_count()
	return _incoming.size() + ws_pending


# 最近一次弹出帧的入队时刻（msec）；仅诊断用（0 = 无）。
func current_arrival_msec() -> int:
	return _current_arrival_msec


# 取出并清零「本窗口内的排队峰值」：诊断里报窗口增量才有意义（累计值看不出是哪一段卡）。
func take_backlog_peak() -> int:
	var v: int = backlog_peak
	backlog_peak = 0
	return v


func _get_max_packet_size() -> int:
	return 1 << 24


func _set_target_peer(p_peer: int) -> void:
	_target_peer = p_peer


func _get_transfer_channel() -> int:
	return _transfer_channel


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _transfer_mode


func _set_transfer_channel(p_channel: int) -> void:
	_transfer_channel = p_channel


func _set_transfer_mode(p_mode: MultiplayerPeer.TransferMode) -> void:
	_transfer_mode = p_mode


func _is_server() -> bool:
	return _unique_id == 1


func _is_server_relay_supported() -> bool:
	return false


func _is_refusing_new_connections() -> bool:
	return _refuse_connections


func _set_refuse_new_connections(p_enable: bool) -> void:
	_refuse_connections = p_enable


func _close() -> void:
	# 主动离开：先发 leave_room，让中继立即 remove_peer。否则要等 TCP FIN / 心跳超时，
	# 期间重复点加入会被中继当作新成员反复分配 peer_id、排到后面。
	if _status == MultiplayerPeer.CONNECTION_CONNECTED:
		_send_control_json({"type": "leave_room"})
	_ws.close()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_unique_id = 0
	_known_peers.clear()
	_incoming.clear()
	_incoming_bytes = 0
	_current_arrival_msec = 0
	backlog_peak = 0
	_peers_to_connect.clear()
	_peers_to_disconnect.clear()
	_pending_peers.clear()
	_admitted.clear()
	_join_handshake_started_msec = 0
	_action_sent = false
	_pending_action = ""
	_pending_token = ""


func _disconnect_peer(p_peer: int, _p_force: bool) -> void:
	# 中继协议（create_room/join_room/client_ready → room_created/...）没有 kick/close_peer 帧，
	# 无法真正让服务端断开某个逻辑 peer；这里只能清本地表。故 host 侧对「未握手/被拒」连接
	# 一律靠 CoopNet._server_sender_ok() 门控其权威 RPC（LAN 的 ENet disconnect_peer 仍直接生效）。
	# 如需真正踢除 Relay 逻辑 peer，需服务端扩展 kick_peer 控制帧。
	_known_peers.erase(p_peer)
