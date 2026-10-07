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


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	remote_effect_freq = clampi(int(cfg.get_value(SECTION, "remote_effect_freq", 4)), 0, 4)
	remote_flash_freq = clampi(int(cfg.get_value(SECTION, "remote_flash_freq", 4)), 0, 4)
	remote_text_freq = clampi(int(cfg.get_value(SECTION, "remote_text_freq", 4)), 0, 4)
	player_id = sanitize_name(str(cfg.get_value(PROFILE_SECTION, "player_id", "")))
	debug_hud = bool(cfg.get_value(DEBUG_SECTION, "debug_hud", false))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "remote_effect_freq", remote_effect_freq)
	cfg.set_value(SECTION, "remote_flash_freq", remote_flash_freq)
	cfg.set_value(SECTION, "remote_text_freq", remote_text_freq)
	cfg.set_value(PROFILE_SECTION, "player_id", player_id)
	cfg.set_value(DEBUG_SECTION, "debug_hud", debug_hud)
	cfg.save(PATH)


func apply_debug_hud(value: bool) -> void:
	debug_hud = value
	save_settings()


func apply_player_id(value: String) -> void:
	player_id = sanitize_name(value)
	save_settings()


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
