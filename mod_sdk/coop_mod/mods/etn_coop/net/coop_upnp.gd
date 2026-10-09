extends Node

## CoopUpnp：host 侧 UPnP 自动端口映射（UDP），供 ENet 直连跨公网。
## 背景：ENet 房主默认只能被局域网/已端口转发的客机连接；UPnP 可向支持的路由器
## 自动申请「公网端口 → 本机端口」映射，让客机用「公网 IP:端口」直连。
##
## 设计：
## - `UPNP.discover()` 会阻塞（实测可达 ~8s，且与 timeout 参数不严格对应），必须放后台线程。
## - `map(port)` 启动线程；完成后（主线程）经 `upnp_ready` / `upnp_failed` 回报。
## - `unmap()` **绝不阻塞主线程**：若线程仍在运行，只置 `_release_pending`，
##   等线程结束后的 `_finish` 在后台删映射；线程已结束时立即删。
## - 同一时刻只允许一个线程：运行中再次 `map` 直接回 `busy`（避免线程引用互相覆盖/泄漏）。
## - 无网关 / 路由器不支持 / CGNAT / 移动端：静默失败，调用方回退 LAN/中继即可。
## mod 内不使用 class_name。

signal upnp_ready(address: String, port: int)
signal upnp_failed(reason: String)   # no_gateway / map_failed / busy / unsupported

var _thread: Thread = null
var _upnp: UPNP = null
var _busy: bool = false
var _mapped_port: int = 0
var _release_pending: bool = false
var external_address: String = ""


func is_busy() -> bool:
	return _busy


func is_mapped() -> bool:
	return _mapped_port > 0 and external_address != ""


# 请求把本机 UDP 端口映射到公网；线程运行中再次调用回 busy。
func map(port: int) -> void:
	if _thread != null and _thread.is_started():
		upnp_failed.emit("busy")
		return
	if port <= 0 or port > 65535:
		upnp_failed.emit("unsupported")
		return
	_release_pending = false
	_busy = true
	_mapped_port = 0
	external_address = ""
	_thread = Thread.new()
	var err := _thread.start(_discover_and_map.bind(port))
	if err != OK:
		_thread = null
		_busy = false
		upnp_failed.emit("unsupported")


# 取消映射：不阻塞；线程运行中则等其结束时清理。
func unmap() -> void:
	external_address = ""
	_release_pending = true
	if _thread == null:
		_delete_mapping()
		_busy = false


func _delete_mapping() -> void:
	if _upnp != null and _mapped_port > 0:
		_upnp.delete_port_mapping(_mapped_port, "UDP")
	_upnp = null
	_mapped_port = 0


func _discover_and_map(port: int) -> void:
	var out: Dictionary = {}
	var upnp := UPNP.new()
	var discover_err: int = upnp.discover(2000, 2)
	var gateway: UPNPDevice = upnp.get_gateway()
	if discover_err != OK or gateway == null or not gateway.is_valid_gateway():
		out["error"] = "no_gateway"
	elif upnp.add_port_mapping(port, port, "ETN Coop", "UDP", 0) != OK:
		out["error"] = "map_failed"
	else:
		out["address"] = gateway.get_external_address()
		out["port"] = port
		out["upnp"] = upnp
	call_deferred("_finish", out)


func _finish(out: Dictionary) -> void:
	if _thread != null:
		if _thread.is_started():
			_thread.wait_to_finish()
		_thread = null
	_busy = false
	# 会话期间已取消：删掉刚建立的映射，不回报
	if _release_pending:
		_release_pending = false
		var stale = out.get("upnp")
		if stale != null and out.has("port"):
			stale.delete_port_mapping(int(out["port"]), "UDP")
		return
	if out.has("error"):
		upnp_failed.emit(str(out["error"]))
		return
	_upnp = out.get("upnp")
	_mapped_port = int(out.get("port", 0))
	external_address = str(out.get("address", ""))
	upnp_ready.emit(external_address, _mapped_port)
