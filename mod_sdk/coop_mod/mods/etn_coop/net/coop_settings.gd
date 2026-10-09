extends RefCounted

## 联机反馈频率设置：仅作用于「其它联机玩家（非本地）」来源的攻击特效。
## 三档独立：特效 / 闪白 / 飘字；语义同本体 game_option：0=关 / 1=×4 / 2=×3 / 3=×2 / 4=×1。
## 本地玩家自身反馈仍由本体 Game.effect_freq / hit_flash_freq / damage_text_freq 管；敌人/Boss 来源同理。

const PATH: String = "user://etn_coop_settings.cfg"
const SECTION: String = "feedback"
const PROFILE_SECTION: String = "profile"
const DEBUG_SECTION: String = "debug"
const MAX_NAME_LEN: int = 12

var remote_effect_freq: int = 4
var remote_flash_freq: int = 4
var remote_text_freq: int = 4
var player_id: String = ""
var debug_hud: bool = false
# UPnP 自动端口映射（默认关）：房主开启后，ENet 直连端口自动映射到公网，客机可用公网 IP 直连。
var upnp_enabled: bool = false
# LAN 直连端口（Host/Join 共用）；默认值与 CoopNet.DEFAULT_PORT 一致。
var lan_port: int = 24591
# 房间标识/复制使用的地址类型：0=局域网（默认）/ 1=公网。
var room_address_mode: int = 0
# 手动公网 IP（可选，持久化）：UPnP 失败时房主手动填入的路由器公网地址；非空则覆盖 UPnP 自动结果。
var manual_public_ip: String = ""
# 稳定客户端令牌（UUID，持久化）：断线重连时 host 用它识别「同一个玩家」并迁移状态。
var client_token: String = ""


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	remote_effect_freq = clampi(int(cfg.get_value(SECTION, "remote_effect_freq", 4)), 0, 4)
	remote_flash_freq = clampi(int(cfg.get_value(SECTION, "remote_flash_freq", 4)), 0, 4)
	remote_text_freq = clampi(int(cfg.get_value(SECTION, "remote_text_freq", 4)), 0, 4)
	player_id = sanitize_name(str(cfg.get_value(PROFILE_SECTION, "player_id", "")))
	debug_hud = bool(cfg.get_value(DEBUG_SECTION, "debug_hud", false))
	upnp_enabled = bool(cfg.get_value(DEBUG_SECTION, "upnp_enabled", false))
	lan_port = clampi(int(cfg.get_value(DEBUG_SECTION, "lan_port", 24591)), 1, 65535)
	room_address_mode = clampi(int(cfg.get_value(DEBUG_SECTION, "room_address_mode", 0)), 0, 1)
	manual_public_ip = str(cfg.get_value(DEBUG_SECTION, "manual_public_ip", "")).strip_edges()
	client_token = str(cfg.get_value(PROFILE_SECTION, "client_token", "")).strip_edges()
	if client_token == "":
		ensure_client_token()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "remote_effect_freq", remote_effect_freq)
	cfg.set_value(SECTION, "remote_flash_freq", remote_flash_freq)
	cfg.set_value(SECTION, "remote_text_freq", remote_text_freq)
	cfg.set_value(PROFILE_SECTION, "player_id", player_id)
	cfg.set_value(PROFILE_SECTION, "client_token", client_token)
	cfg.set_value(DEBUG_SECTION, "debug_hud", debug_hud)
	cfg.set_value(DEBUG_SECTION, "upnp_enabled", upnp_enabled)
	cfg.set_value(DEBUG_SECTION, "lan_port", lan_port)
	cfg.set_value(DEBUG_SECTION, "room_address_mode", room_address_mode)
	cfg.set_value(DEBUG_SECTION, "manual_public_ip", manual_public_ip)
	cfg.save(PATH)


func apply_debug_hud(value: bool) -> void:
	debug_hud = value
	save_settings()


func apply_upnp_enabled(value: bool) -> void:
	upnp_enabled = value
	save_settings()


func apply_lan_port(value: int) -> void:
	lan_port = clampi(value, 1, 65535)
	save_settings()


func apply_room_address_mode(value: int) -> void:
	room_address_mode = clampi(value, 0, 1)
	save_settings()


func apply_manual_public_ip(value: String) -> void:
	manual_public_ip = value.strip_edges()
	save_settings()


func apply_player_id(value: String) -> void:
	player_id = sanitize_name(value)
	save_settings()


# 确保存在稳定客户端令牌（UUID）；首启生成并落盘，之后跨会话保持。
func ensure_client_token() -> String:
	if client_token == "":
		var crypto := Crypto.new()
		client_token = crypto.generate_random_bytes(16).hex_encode()
		save_settings()
	return client_token


# 名称清洗：去掉换行与首尾空白（长度校验由调用方负责）。
static func sanitize_name(value: String) -> String:
	return value.replace("\n", "").replace("\r", "").strip_edges()


func apply_remote_effect(value: int) -> void:
	remote_effect_freq = clampi(value, 0, 4)
	save_settings()


func apply_remote_flash(value: int) -> void:
	remote_flash_freq = clampi(value, 0, 4)
	save_settings()


func apply_remote_text(value: int) -> void:
	remote_text_freq = clampi(value, 0, 4)
	save_settings()


# 档位 -> 间隔倍数（0 表示关闭，由调用方特判）
static func freq_mult(freq: int) -> int:
	match freq:
		0:
			return 0
		1:
			return 4
		2:
			return 3
		3:
			return 2
	return 1
