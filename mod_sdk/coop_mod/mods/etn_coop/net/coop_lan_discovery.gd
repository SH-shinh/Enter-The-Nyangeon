extends Node

## CoopLanDiscovery：LAN 房间发现（UDP 广播，独立于 ENet）。
## host：advertise_ensure(info) 后每 ADVERTISE_INTERVAL 秒向 255.255.255.255 广播房间 JSON。
## client：browse_start() 收包，按 ip:port 去重、超时剔除；get_rooms() 取列表。
## 失败（端口占用/广播受限）一律静默，手动输 IP 仍可用。
## mod 内不使用 class_name。

const DISCOVERY_PORT: int = 24592
const MAGIC: String = "ETN_COOP"
const PROTOCOL_VERSION: int = 1
const ADVERTISE_INTERVAL: float = 1.0
const ROOM_TIMEOUT_MSEC: int = 2500

var _adv_socket: PacketPeerUDP = null
var _adv_timer: float = 0.0
var _adv_info: Dictionary = {}

var _browse_socket: PacketPeerUDP = null
var _rooms: Dictionary = {}   # "ip:port" -> {ip, port, name, players, max, mode, game_version, last_ms}


func advertise_ensure(info: Dictionary) -> void:
	_adv_info = info
	if _adv_socket == null:
		_adv_socket = PacketPeerUDP.new()
		_adv_socket.set_broadcast_enabled(true)
		# 只发送不监听 → 绑临时端口，避免与本机/他人 browse 抢 DISCOVERY_PORT
		if _adv_socket.bind(0) != OK:
			_adv_socket = null
			return
		_adv_timer = ADVERTISE_INTERVAL
		_send_advertise()
	set_process(true)


func advertise_stop() -> void:
	if _adv_socket != null:
		_adv_socket.close()
	_adv_socket = null


func is_advertising() -> bool:
	return _adv_socket != null


func browse_start() -> void:
	if _browse_socket != null:
		return
	var s := PacketPeerUDP.new()
	if s.bind(DISCOVERY_PORT) != OK:
		s.close()
		s = PacketPeerUDP.new()
		if s.bind(0) != OK:
			return
	_browse_socket = s
	set_process(true)


func browse_stop() -> void:
	if _browse_socket != null:
		_browse_socket.close()
	_browse_socket = null
	_rooms.clear()


func is_browsing() -> bool:
	return _browse_socket != null


func get_rooms() -> Array:
	_prune()
	var arr: Array = _rooms.values()
	arr.sort_custom(func(a, b): return int(a.get("players", 0)) > int(b.get("players", 0)))
	return arr


func _send_advertise() -> void:
	if _adv_socket == null:
		return
	var payload := {
		"magic": MAGIC,
		"pv": PROTOCOL_VERSION,
		"name": str(_adv_info.get("name", "")),
		"port": int(_adv_info.get("port", 24591)),
		"players": int(_adv_info.get("players", 1)),
		"max": int(_adv_info.get("max", 4)),
		"mode": str(_adv_info.get("mode", "")),
		"game_version": str(_adv_info.get("game_version", "")),
	}
	_adv_socket.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_adv_socket.put_packet(JSON.stringify(payload).to_utf8_buffer())
	# 同机自测兜底：再单播一份到回环（广播在同机跨进程有时不回流）
	_adv_socket.set_dest_address("127.0.0.1", DISCOVERY_PORT)
	_adv_socket.put_packet(JSON.stringify(payload).to_utf8_buffer())


func _receive() -> void:
	if _browse_socket == null:
		return
	while _browse_socket.get_available_packet_count() > 0:
		var pkt := _browse_socket.get_packet()
		var ip := _browse_socket.get_packet_ip()
		var data = JSON.parse_string(pkt.get_string_from_utf8())
		if not (data is Dictionary) or str(data.get("magic", "")) != MAGIC:
			continue
		if int(data.get("pv", 0)) != PROTOCOL_VERSION:
			continue
		var port := int(data.get("port", 24591))
		_rooms["%s:%d" % [ip, port]] = {
			"ip": ip,
			"port": port,
			"name": str(data.get("name", "")),
			"players": int(data.get("players", 0)),
			"max": int(data.get("max", 0)),
			"mode": str(data.get("mode", "")),
			"game_version": str(data.get("game_version", "")),
			"last_ms": Time.get_ticks_msec(),
		}


func _prune() -> void:
	var now: int = Time.get_ticks_msec()
	for k in _rooms.keys():
		if now - int(_rooms[k]["last_ms"]) > ROOM_TIMEOUT_MSEC:
			_rooms.erase(k)


func _process(delta: float) -> void:
	if _adv_socket != null:
		_adv_timer -= delta
		if _adv_timer <= 0.0:
			_adv_timer = ADVERTISE_INTERVAL
			_send_advertise()
	if _browse_socket != null:
		_receive()
	if _adv_socket == null and _browse_socket == null:
		set_process(false)
