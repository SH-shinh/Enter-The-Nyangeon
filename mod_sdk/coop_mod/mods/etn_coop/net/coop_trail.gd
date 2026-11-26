extends RefCounted

## CoopTrail：联机「面包屑」日志（崩溃现场取证用，纯 mod）。
##
## 目标：release 包没有 crash handler，玩家闪退后只剩一份停在半路的 ETN_debug.log。
## 这里把「事件级」的关键节点（不是逐帧）按行写盘并立即 flush：崩溃时最后一行就是现场。
##
## 约束：
## - 只记事件，不逐帧；全局限速（MAX_LINES_PER_SEC），避免低端机 IO 抖动/帧时间被拖。
## - 单文件上限 MAX_BYTES，超过就轮转，最多保留 MAX_FILES 份。
## - 自身任何失败都静默（绝不 push_error），不影响联机主流程。
## - 由 coop_settings.debug 的 network_trail 开关控制（默认开）。

const PATH: String = "user://logs/coop_trail.log"
const DIR: String = "user://logs"
const MAX_FILES: int = 3
const MAX_BYTES: int = 262144
const MAX_LINES_PER_SEC: int = 50
const MAX_DETAIL: int = 160
const MEM_HEARTBEAT_MSEC: int = 10000

static var _file: FileAccess = null
static var _enabled: bool = true
static var _sealed: bool = false
static var _bytes: int = 0


# 当前文件已写字节数（诊断用：PERF 行统计 trail 写入量）
static func bytes() -> int:
	return _bytes
static var _rate_window_msec: int = 0
static var _rate_lines: int = 0
static var _dropped: int = 0
static var _last_mem_msec: int = 0


# 由 CoopNet 在 _ready 按设置调用；false 时连已打开的文件也关掉。
static func configure(enabled: bool) -> void:
	_enabled = enabled
	if not _enabled:
		close()


static func is_enabled() -> bool:
	return _enabled


static func open() -> void:
	if not _enabled or _sealed or _file != null:
		return
	if not DirAccess.dir_exists_absolute(DIR):
		DirAccess.make_dir_recursive_absolute(DIR)
	_rotate_if_needed()
	# 用 READ_WRITE + seek_end 追加，绝不能用 WRITE（会截断）：
	# _notification 的 EXIT_TREE/PREDELETE 会 close 两次，之后任何 mark 自动重开会把整份现场清空。
	_file = FileAccess.open(PATH, FileAccess.READ_WRITE)
	if _file == null:
		_file = FileAccess.open(PATH, FileAccess.WRITE)
	if _file == null:
		# 主日志被其它实例占用（Windows 上会出现）：退到带 PID 的独立文件。
		# 否则后续所有埋点会被静默丢弃（本机 12 个残留进程就造成过整份现场缺失）。
		var alt: String = "user://logs/coop_trail_%d.log" % OS.get_process_id()
		_file = FileAccess.open(alt, FileAccess.WRITE)
		if _file != null:
			push_warning("[etn_coop] trail log busy; fallback to %s" % alt)
	if _file != null:
		_file.seek_end()
		_bytes = int(_file.get_position())
	_rate_window_msec = 0
	_rate_lines = 0
	_dropped = 0
	_last_mem_msec = 0
	if _file != null:
		mark("trail", "open v=%s" % _engine_note())


static func close() -> void:
	if _file == null:
		return
	_file.store_line("%d|%s|%s|%s" % [Time.get_ticks_msec(), "", "trail", "close dropped=%d" % _dropped])
	_file.flush()
	_file.close()
	_file = null


# 进程退出路径专用：写完最后一行后封存，后续 mark 不再重开文件（避免覆盖崩溃现场）。
static func seal() -> void:
	_sealed = true
	close()


# 记录一条事件：tag 供检索，detail 允许换行（会被压平）且长度截断。
static func mark(tag: String, detail: String = "") -> void:
	if not _enabled:
		return
	if _file == null:
		open()
		if _file == null:
			return
	var now: int = Time.get_ticks_msec()
	if now - _rate_window_msec >= 1000:
		_rate_window_msec = now
		_rate_lines = 0
	if _rate_lines >= MAX_LINES_PER_SEC:
		_dropped += 1
		return
	_rate_lines += 1
	var text: String = str(detail).replace("\n", " ").replace("\r", " ")
	if text.length() > MAX_DETAIL:
		text = text.substr(0, MAX_DETAIL)
	var line: String = "%d|%s|%s|%s" % [now, _scene_path(), tag, text]
	_file.store_line(line)
	_file.flush()
	_bytes += line.length() + 1
	if _bytes > MAX_BYTES:
		close()
		_rotate_if_needed()
		_bytes = 0


# 10s 一次的内存心跳：用于区分「原生崩溃」与「内存涨爆/被系统杀」，并观察跨局泄漏。
static func heartbeat(extra: String = "") -> void:
	if not _enabled:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_mem_msec < MEM_HEARTBEAT_MSEC:
		return
	_last_mem_msec = now
	var static_mb: float = float(OS.get_static_memory_usage()) / 1048576.0
	var perf_mb: float = float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0
	mark("mem", "static=%.1fMB perf=%.1fMB %s" % [static_mb, perf_mb, extra])


static func _scene_path() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null or not is_instance_valid(tree.current_scene):
		return ""
	return str(tree.current_scene.scene_file_path)


static func _rotate_if_needed() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var size: int = 0
	var probe := FileAccess.open(PATH, FileAccess.READ)
	if probe != null:
		size = probe.get_length()
		probe.close()
	if size <= 0 or size < MAX_BYTES:
		return
	# 只保留 MAX_FILES 份：coop_trail.log.2 丢弃，.1 -> .2，base -> .1
	if FileAccess.file_exists(PATH + ".2"):
		DirAccess.remove_absolute(PATH + ".2")
	if FileAccess.file_exists(PATH + ".1"):
		DirAccess.rename_absolute(PATH + ".1", PATH + ".2")
	DirAccess.rename_absolute(PATH, PATH + ".1")


static func _engine_note() -> String:
	return "%s" % str(ProjectSettings.get_setting("application/config/name", ""))
