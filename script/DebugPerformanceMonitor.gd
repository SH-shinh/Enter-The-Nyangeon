extends CanvasLayer

## 调试性能面板（F3 开关）：帧耗时 / 进程与物理耗时 / 渲染提交 / 节点与内存 / 对象池。
## F2 开关：隐藏/恢复所有敌人头顶 UI（`MarginContainer`：HP 条 + BuffCard）——
##   已移到控制台菜单的 `HideOverheadUI`（F2 是 `cheat_menu` 的绑定键，这里不再抢热键）。
##   用于 A/B 判断「UI 布局 / 文本更新（C++ 侧，不进 Script 计时）」是不是尖峰主因；切换会写日志标记。
## 已是 `project.godot` 的 autoload（`DebugPerformanceMonitor="*res://ui/debug_performance_monitor.tscn"`，全局一份），
## 不要再把它挂进任何场景（会变成第二份实例，日志/采样翻倍；`_ready` 里有单实例保护兜底）。
## 单实例保护：切场景/重开残留的第二份实例会在 `_ready` 里自行销毁，避免重复采样与重复日志行。
##
## 采样常驻（每帧几次浮点累加 + 1 次 Performance 读），只有面板可见时才以 4Hz 重建文本。
## 判读峰值请看前两行：
##   `frame  mean/max`  = 最近一次刷新窗口（≈0.25s）内的帧耗时；`peak` = 本次运行最大帧；
##   `spikes`           = 超过 SPIKE_MS(25ms) 的帧数（窗口/会话）；
##   `eng proc` / `phys` = 引擎 TIME_PROCESS / TIME_PHYSICS_PROCESS 的窗口 mean/max。
##     引擎监视器在部分机器上的读数会大于帧时间（口径不一致），此时行尾带 `(!)`，**不要据此判断脚本/渲染**。
## 尖峰帧会用黄字提示，并在底部固定显示**最近 3 次尖峰帧的快照**（两行/条），所以不必「正好停在尖峰那一帧」也能取证：
##   `sp1 40.8ms d=1369 o=4667 E=98 B=205 res=4096(d=0) vm=412 p2d=380/1130`
##   `     cas=64/64 coin=82/84 ftxt=80/100 pbul=80/150 pool=465/576 proc=28.6 phys=8.2`
## 判读：尖峰帧 `d/o` 不比平静帧高 ⇒ 不是「东西太多」；`res(d=+N)`/`vm` 跳 ⇒ 资源加载/纹理上传；
##       `p2d` 跳 ⇒ 物理；`cas/coin/ftxt` 跳 ⇒ 生成爆发。每条快照同时追加到 `user://logs/perf_spikes.log`。

const UPDATE_INTERVAL: float = 0.25
## 单帧超过该毫秒数记一次「尖峰」（60fps 预算 16.7ms，明显掉帧阈值）。
const SPIKE_MS: float = 25.0
const SPIKE_COLOR := Color(1, 0.85, 0.3, 1)
const NORMAL_COLOR := Color(0.85, 1, 0.85, 1)
## 尖峰快照环形缓冲容量（只保留最近 N 条，显示最近 3 条）。
const MAX_SPIKES: int = 6
## 两次快照的最小间隔：避免连续掉帧时每帧都去读池统计。
const SPIKE_CAPTURE_GAP_MS: float = 120.0
## 尖峰明细落盘（会话开始截断），方便事后直接读文件而不用截图。
const SPIKE_LOG_PATH := "user://logs/perf_spikes.log"

@onready var panel: PanelContainer = $PanelContainer
@onready var label: Label = $PanelContainer/MarginContainer/Label

var visible_overlay: bool = false
var update_time: float = 0.0

# 最近刷新窗口（每次重建文本后清零）
var _win_frames: int = 0
var _win_sum_ms: float = 0.0
var _win_max_ms: float = 0.0
var _win_spikes: int = 0
var _win_proc_sum: float = 0.0
var _win_proc_max: float = 0.0
var _win_phys_sum: float = 0.0
var _win_phys_max: float = 0.0
# 会话累计
var _session_max_ms: float = 0.0
var _session_spikes: int = 0
# 最近尖峰帧快照（dt/proc/phys/draws/objs/prim/nodes/enemies/bullets/se/res/res_delta/vmem/p2d/池）
var _spikes: Array = []
var _last_spike_capture_ms: float = -100000.0
## 上一帧的资源数：尖峰帧的 res 增量用来判断「是否刚发生资源加载/首次使用」。-1 = 还没采过（首帧不算增量）。
var _prev_res: int = -1
## 敌人头顶 UI（HP 条 + BuffCard）是否被 F2 隐藏（A/B 用）。
var _overhead_hidden: bool = false
## 单实例保护：切场景/重开残留可能同时存在两份，会重复采样、把日志写成两行。
static var _instance_count: int = 0
var _counted: bool = false


func _ready() -> void:
	_instance_count += 1
	_counted = true
	if _instance_count > 1:
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	_init_spike_log()


func _exit_tree() -> void:
	if _counted:
		_counted = false
		_instance_count -= 1


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F3:
		visible_overlay = not visible_overlay
		panel.visible = visible_overlay
		update_time = UPDATE_INTERVAL
		_reset_window()
		if visible_overlay:
			# 打开时清掉会话峰值，避免把「加载/切场景」的启动尖峰当成战斗中峰值。
			_session_max_ms = 0.0
			_session_spikes = 0
			_spikes.clear()


func _process(delta: float) -> void:
	_sample(delta)
	if not visible_overlay:
		return
	update_time += delta
	if update_time < UPDATE_INTERVAL:
		return
	update_time = 0.0
	label.text = _build_debug_text()
	label.add_theme_color_override("font_color", SPIKE_COLOR if _win_spikes > 0 else NORMAL_COLOR)
	_reset_window()


## 隐藏/恢复所有敌人头顶 UI（血条 + BuffCard），用于 A/B 判断「UI 布局/文本（C++）是否尖峰主因」。
## 由控制台菜单 `Panel/VBox/Actions/Debug/HideOverheadUI` 驱动——F2 是 `cheat_menu` 的绑定键，
## 调试开关一律进控制台，不要再抢热键（否则 dev_mode 下会被 `set_input_as_handled` 吞掉）。
func set_overhead_hidden(hidden: bool) -> void:
	if _overhead_hidden == hidden:
		return
	_overhead_hidden = hidden
	# 敌人侧自己管「在屏内」的裁剪；这里只同步全局开关，再由各敌人重算最终可见性。
	Enemy.overhead_ui_globally_hidden = hidden
	var tree: SceneTree = get_tree()
	if tree != null:
		for e in tree.get_nodes_in_group("Enemy"):
			if e == null or not is_instance_valid(e):
				continue
			if e.has_method("_apply_overhead_visibility"):
				e.call("_apply_overhead_visibility")
	_append_log_raw("=== toggle enemy_overhead_ui=%s (f=%d) ===" % [
		"off" if _overhead_hidden else "on", Engine.get_process_frames()])


func is_overhead_hidden() -> bool:
	return _overhead_hidden


func _sample(delta: float) -> void:
	var ms: float = delta * 1000.0
	if ms > _session_max_ms:
		_session_max_ms = ms
	_win_frames += 1
	_win_sum_ms += ms
	if ms > _win_max_ms:
		_win_max_ms = ms
	var proc_ms: float = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var phys_ms: float = float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	_win_proc_sum += proc_ms
	_win_phys_sum += phys_ms
	if proc_ms > _win_proc_max:
		_win_proc_max = proc_ms
	if phys_ms > _win_phys_max:
		_win_phys_max = phys_ms
	# 资源数：每帧读一次，尖峰帧用「相对上一帧的增量」判断是否刚发生加载/首次使用。
	var res_now: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var res_delta: int = 0 if _prev_res < 0 else res_now - _prev_res
	_prev_res = res_now
	if ms >= SPIKE_MS:
		_win_spikes += 1
		_session_spikes += 1
		_capture_spike(ms, proc_ms, phys_ms, res_now, res_delta)


# 抓一张尖峰帧画像：先更新计数器，再读当时的渲染/实体/物理/池状态，存进环形缓冲并落盘。
func _capture_spike(dt_ms: float, proc_ms: float, phys_ms: float, res_now: int, res_delta: int) -> void:
	var now: float = float(Time.get_ticks_msec())
	if now - _last_spike_capture_ms < SPIKE_CAPTURE_GAP_MS:
		return
	_last_spike_capture_ms = now
	var pool_stats: Dictionary = _get_pool_stats()
	var snap: Dictionary = {
		"dt": dt_ms,
		"proc": proc_ms,
		"phys": phys_ms,
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"objs": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"prim": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"enemies": _child_count(get_tree().get_first_node_in_group("EnemiesRoot")),
		"bullets": _child_count(get_tree().get_first_node_in_group("BulletRoot")),
		"se": _child_count(get_tree().get_first_node_in_group("SELayer")),
		"res": res_now,
		"res_delta": res_delta,
		"vmem": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		"p2d_active": int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
		"p2d_pairs": int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
		"cas": _pool_text(pool_stats["raw"], "casing"),
		"coin": _pool_text(pool_stats["raw"], "coin"),
		"ftxt": _pool_text(pool_stats["raw"], "floating_text"),
		"pbul": _pool_text(pool_stats["raw"], "player_bullet"),
		"pool_active": int(pool_stats["active"]),
		"pool_total": int(pool_stats["total"]),
	}
	_spikes.append(snap)
	while _spikes.size() > MAX_SPIKES:
		_spikes.pop_front()
	_append_spike_log(snap)


func _pool_text(stats: Dictionary, id: String) -> String:
	if not stats.has(id):
		return "-"
	var s: Dictionary = stats[id]
	return "%d/%d" % [int(s["active"]), int(s["total"])]


func _init_spike_log() -> void:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null and not dir.dir_exists("logs"):
		dir.make_dir("logs")
	var f: FileAccess = FileAccess.open(SPIKE_LOG_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("=== perf spikes %s ===" % Time.get_datetime_string_from_system())
	f.close()


func _append_spike_log(s: Dictionary) -> void:
	_append_log_raw("f=%d t=%.3f | dt=%.1f draws=%d objs=%d prim=%d nodes=%d E=%d B=%d SE=%d res=%d(d=%d) vmem=%dMB p2d=%d/%d cas=%s coin=%s ftxt=%s pbul=%s pool=%d/%d proc=%.1f phys=%.1f" % [
		Engine.get_process_frames(), Time.get_unix_time_from_system(),
		float(s["dt"]), int(s["draws"]), int(s["objs"]), int(s["prim"]), int(s["nodes"]),
		int(s["enemies"]), int(s["bullets"]), int(s["se"]),
		int(s["res"]), int(s["res_delta"]), int(s["vmem"]),
		int(s["p2d_active"]), int(s["p2d_pairs"]),
		str(s["cas"]), str(s["coin"]), str(s["ftxt"]), str(s["pbul"]),
		int(s["pool_active"]), int(s["pool_total"]),
		float(s["proc"]), float(s["phys"]),
	])


## 追加一行到尖峰日志（快照与切换标记共用）。
func _append_log_raw(line: String) -> void:
	var f: FileAccess = FileAccess.open(SPIKE_LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(line)
	f.close()


func _spike_lines() -> String:
	if _spikes.is_empty():
		return "last spikes: (none)"
	var parts: Array[String] = ["last spikes:"]
	var start: int = maxi(0, _spikes.size() - 3)
	var n: int = 1
	for i in range(start, _spikes.size()):
		var s: Dictionary = _spikes[i]
		parts.append(" sp%d %.1fms d=%d o=%d E=%d B=%d res=%d(d=%d) vm=%d p2d=%d/%d" % [
			n, float(s["dt"]), int(s["draws"]), int(s["objs"]),
			int(s["enemies"]), int(s["bullets"]), int(s["res"]), int(s["res_delta"]),
			int(s["vmem"]), int(s["p2d_active"]), int(s["p2d_pairs"])])
		parts.append("     cas=%s coin=%s ftxt=%s pbul=%s pool=%d/%d proc=%.1f phys=%.1f" % [
			str(s["cas"]), str(s["coin"]), str(s["ftxt"]), str(s["pbul"]),
			int(s["pool_active"]), int(s["pool_total"]), float(s["proc"]), float(s["phys"])])
		n += 1
	return "\n".join(parts)


func _reset_window() -> void:
	_win_frames = 0
	_win_sum_ms = 0.0
	_win_max_ms = 0.0
	_win_spikes = 0
	_win_proc_sum = 0.0
	_win_proc_max = 0.0
	_win_phys_sum = 0.0
	_win_phys_max = 0.0


func _build_debug_text() -> String:
	var frames: float = maxf(1.0, float(_win_frames))
	var bullet_root: Node = get_tree().get_first_node_in_group("BulletRoot")
	var enemy_root: Node = get_tree().get_first_node_in_group("EnemiesRoot")
	var se_layer: Node = get_tree().get_first_node_in_group("SELayer")
	var foreground_layer: Node = get_tree().get_first_node_in_group("ForegroundLayer")
	var pool_stats: Dictionary = _get_pool_stats()
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var prims: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var res: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var mem_mb: int = int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
	# 引擎监视器与帧时间矛盾时打 (!)，提示这行不能作为「脚本 vs 渲染」的判据。
	var proc_flag: String = " (!)" if (_win_frames >= 2 and _win_proc_max > _win_max_ms * 1.2) else ""
	return "\n".join([
		"F3 perf  (F3 hide)",
		"FPS %d   frame %.1f/%.1fms  peak %.1f" % [
			Engine.get_frames_per_second(), _win_sum_ms / frames, _win_max_ms, _session_max_ms],
		"spikes>=%dms  win %d  session %d" % [int(SPIKE_MS), _win_spikes, _session_spikes],
		"eng proc %.1f/%.1f  phys %.1f/%.1f%s" % [
			_win_proc_sum / frames, _win_proc_max, _win_phys_sum / frames, _win_phys_max, proc_flag],
		"draws %d  objs %d  prim %dk" % [draws, objs, int(prims / 1000.0)],
		"nodes %d  orphan %d  res %d  mem %dMB" % [nodes, orphans, res, mem_mb],
		"Enemies %d  Bullets %d  SE %d  FG %d" % [
			_child_count(enemy_root), _child_count(bullet_root),
			_child_count(se_layer), _child_count(foreground_layer)],
		"Pool active/total %d/%d  pools %d" % [pool_stats["active"], pool_stats["total"], pool_stats["pool_count"]],
		"Top pools:",
		pool_stats["top_pools"],
		_spike_lines(),
	])


func _child_count(node: Node) -> int:
	if node == null:
		return 0
	return node.get_child_count()


func _get_pool_stats() -> Dictionary:
	var stats: Dictionary = PoolManager.pool_stats()
	var active: int = 0
	var total: int = 0
	for id in stats.keys():
		active += int(stats[id]["active"])
		total += int(stats[id]["total"])
	return {
		"active": active,
		"total": total,
		"pool_count": stats.size(),
		"top_pools": _get_top_pool_text(stats),
		"raw": stats,
	}


func _get_top_pool_text(stats: Dictionary) -> String:
	var entries: Array[Dictionary] = []
	for id in stats.keys():
		var s: Dictionary = stats[id]
		entries.append({
			"name": str(id),
			"active": int(s["active"]),
			"total": int(s["total"]),
			"limit": int(s["limit"]),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["total"] > b["total"])
	var parts: Array[String] = []
	for i in min(4, entries.size()):
		parts.append("  %s=%d/%d idle_cap=%d" % [entries[i]["name"], entries[i]["active"], entries[i]["total"], entries[i]["limit"]])
	return "\n".join(parts)
