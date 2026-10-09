extends RefCounted

## CoopNetworkTransport：LAN（ENet）与中继（WebSocket）传输工厂。
## mod 内不使用 class_name，调用方以 preload 常量引用。

enum Mode { OFFLINE, LAN, RELAY }

const RelayPeerScript := preload("res://mods/etn_coop/net/coop_relay_peer.gd")
const HOST_ROLE: String = "host"
const CLIENT_ROLE: String = "client"

var mode: Mode = Mode.OFFLINE
var peer: MultiplayerPeer = null
var status_message: String = ""
var relay_room_code: String = ""


static func create_lan_host(port: int, max_players: int):
	var t = new()
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_server(port, max_players)
	if err != OK:
		t.status_message = "Host failed: %s" % err
		return t
	t.mode = Mode.LAN
	t.peer = enet
	return t


static func create_lan_client(ip: String, port: int):
	var t = new()
	var enet := ENetMultiplayerPeer.new()
	var err := enet.create_client(ip, port)
	if err != OK:
		t.status_message = "Join failed: %s" % err
		return t
	t.mode = Mode.LAN
	t.peer = enet
	return t


static func create_relay(server_url: String, room_code: String, role: String, token: String = ""):
	var t = new()
	var clean_room: String = sanitize_room_code(room_code)
	if clean_room == "" and role != HOST_ROLE:
		t.status_message = "Relay failed: room code is empty"
		return t
	var relay = RelayPeerScript.new()
	var url: String = build_relay_url(server_url)
	var err: Error
	if role == HOST_ROLE:
		err = relay.create_relay_host(url, "Player", token)
	else:
		err = relay.join_relay_room(url, clean_room, "Player", token)
	if err != OK:
		t.status_message = "Relay failed: %s (%s)" % [_error_to_text(err), url]
		return t
	t.mode = Mode.RELAY
	t.peer = relay
	t.relay_room_code = clean_room
	return t


static func build_relay_url(server_url: String) -> String:
	var url: String = server_url.strip_edges()
	if url == "":
		url = "ws://127.0.0.1:7716"
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		url = "ws://" + url
	return _ensure_path_before_query(url)


static func sanitize_room_code(room_code: String) -> String:
	return room_code.strip_edges().to_upper().replace(" ", "")


static func _ensure_path_before_query(url: String) -> String:
	var scheme_index: int = url.find("://")
	if scheme_index < 0:
		return url
	var host_start: int = scheme_index + 3
	var query_index: int = url.find("?", host_start)
	var slash_index: int = url.find("/", host_start)
	if slash_index >= 0 and (query_index < 0 or slash_index < query_index):
		return url
	if query_index >= 0:
		return url.substr(0, query_index) + "/" + url.substr(query_index)
	return url + "/"


static func _error_to_text(error: Error) -> String:
	match error:
		ERR_CANT_CONNECT:
			return "ERR_CANT_CONNECT"
		ERR_CANT_RESOLVE:
			return "ERR_CANT_RESOLVE"
		ERR_INVALID_PARAMETER:
			return "ERR_INVALID_PARAMETER"
		ERR_UNAVAILABLE:
			return "ERR_UNAVAILABLE"
		_:
			return str(error)
