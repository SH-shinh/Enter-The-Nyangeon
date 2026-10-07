extends MultiplayerPeerExtension

## CoopRelayPeer：WebSocket 中继 MultiplayerPeer（移植自 coop 实现）。
## 依赖外部中继服务端（协议：create_room/join_room → room_created/join_prepared/join_admitted/peer_*）。
## mod 内不使用 class_name。

signal relay_room_created(room_code: String)
signal relay_room_joined(peer_id: int)
signal relay_error(message: String)

const JOIN_HANDSHAKE_TIMEOUT_MSEC: int = 15000
const CONNECT_TIMEOUT_MSEC: int = 10000

var _ws := WebSocketPeer.new()
var _unique_id: int = 0
var _status: MultiplayerPeer.ConnectionStatus = MultiplayerPeer.CONNECTION_DISCONNECTED
var _target_peer: int = 0
var _transfer_mode: MultiplayerPeer.TransferMode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _transfer_channel: int = 0
var _refuse_connections: bool = false
var _incoming: Array[Dictionary] = []
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
var _action_sent: bool = false
var _admitted: Dictionary = {}          # peer_id -> true（已 emit 过 peer_connected，防重复接入）
var _relay_debug: bool = OS.is_debug_build()


# 排入待接入列表（去重 + 跳过自身/0）。真正 emit 在 _poll 末尾统一做。
func _queue_peer(peer_id: int) -> void:
	if peer_id <= 0 or peer_id == _unique_id:
		return
	if _admitted.has(peer_id) or _peers_to_connect.has(peer_id):
		return
	_peers_to_connect.append(peer_id)


func create_relay_host(url: String, player_name: String) -> Error:
	_pending_action = "create"
	_pending_name = player_name
	_action_sent = false
	_connect_started_msec = Time.get_ticks_msec()
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	var error := _ws.connect_to_url(url)
	if error != OK:
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		_connect_started_msec = 0
	return error


func join_relay_room(url: String, room_code: String, player_name: String) -> Error:
	_pending_action = "join"
	_pending_name = player_name
	_pending_room_code = room_code
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
		if _pending_action == "create":
			_ws.send_text(JSON.stringify({
				"type": "create_room",
				"player_name": _pending_name,
			}))
		elif _pending_action == "join":
			_ws.send_text(JSON.stringify({
				"type": "join_room",
				"room_code": _pending_room_code,
				"player_name": _pending_name,
			}))
		_pending_action = ""

	while _ws.get_available_packet_count() > 0:
		var packet := _ws.get_packet()
		if _ws.was_string_packet():
			_on_control(packet.get_string_from_utf8())
		else:
			_on_data(packet)

	for peer_id in _peers_to_connect:
		if not _admitted.has(peer_id):
			_admitted[peer_id] = true
			if _relay_debug:
				print("[etn_coop][relay] admit peer=%d" % peer_id)
			emit_signal("peer_connected", peer_id)
	_peers_to_connect.clear()

	for peer_id in _peers_to_disconnect:
		emit_signal("peer_disconnected", peer_id)
	_peers_to_disconnect.clear()


func _on_control(text: String) -> void:
	var data = JSON.parse_string(text)
	if not (data is Dictionary):
		return
	if _relay_debug:
		print("[etn_coop][relay] <- %s" % text)
	match data.get("type", ""):
		"room_created":
			_unique_id = int(data.get("peer_id", 1))
			_known_peers[_unique_id] = "self"
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			relay_room_created.emit(str(data.get("room_code", "")))
		"join_prepared":
			_unique_id = int(data.get("peer_id", 0))
			_join_handshake_started_msec = Time.get_ticks_msec()
			_pending_peers.clear()
			for peer_info in data.get("peers", []):
				var peer_id := int(peer_info.get("peer_id", 0))
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
			_admitted.erase(disconnected_peer_id)
			_peers_to_disconnect.append(disconnected_peer_id)
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
	var source := packet.decode_s32(0)
	# 收到谁的数据就接入谁（房主无需依赖服务端 join 通知）；_poll 在引擎 drain 前统一 emit。
	_queue_peer(source)
	var payload := packet.slice(4)
	_incoming.append({
		"data": payload,
		"peer": source,
		"channel": 0,
		"mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE,
	})


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	var packet: Dictionary = _incoming.pop_front()
	_current_pkt_peer = packet["peer"]
	_current_pkt_channel = packet["channel"]
	_current_pkt_mode = packet["mode"]
	return packet["data"]


func _get_packet_peer() -> int:
	return _current_pkt_peer


func _get_packet_channel() -> int:
	return _current_pkt_channel


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _current_pkt_mode


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	var header := PackedByteArray()
	header.resize(4)
	header.encode_s32(0, _target_peer)
	_ws.send(header + p_buffer)
	return OK


func _get_unique_id() -> int:
	return _unique_id


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


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
	_ws.close()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_unique_id = 0
	_known_peers.clear()
	_incoming.clear()
	_peers_to_connect.clear()
	_peers_to_disconnect.clear()
	_pending_peers.clear()
	_admitted.clear()
	_join_handshake_started_msec = 0
	_action_sent = false
	_pending_action = ""


func _disconnect_peer(p_peer: int, _p_force: bool) -> void:
	_known_peers.erase(p_peer)
