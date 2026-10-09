extends CanvasLayer

## 调试性能面板（F3 开关）：FPS、各层子节点数、对象池汇总与 Top 池。
## 自联机版（ETN_coop 0.4.1.3）DebugPerformanceMonitor 迁移：
##  - 池统计改走 PoolManager 公开接口 `pool_stats()`，不再直读 `PoolManager.pool` 内部。
##  - 网络两行为占位（本体无 NetworkManager）。
## 无门控：任何构建下 F3 均可切换。

const UPDATE_INTERVAL: float = 0.25

@onready var panel: PanelContainer = $PanelContainer
@onready var label: Label = $PanelContainer/MarginContainer/Label

var visible_overlay: bool = false
var update_time: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible_overlay = not visible_overlay
		panel.visible = visible_overlay
		update_time = UPDATE_INTERVAL

func _process(delta: float) -> void:
	if not visible_overlay:
		return
	update_time += delta
	if update_time < UPDATE_INTERVAL:
		return
	update_time = 0.0
	label.text = _build_debug_text()

func _build_debug_text() -> String:
	var bullet_root: Node = get_tree().get_first_node_in_group("BulletRoot")
	var enemy_root: Node = get_tree().get_first_node_in_group("EnemiesRoot")
	var se_layer: Node = get_tree().get_first_node_in_group("SELayer")
	var foreground_layer: Node = get_tree().get_first_node_in_group("ForegroundLayer")
	var pool_stats: Dictionary = _get_pool_stats()

	return "\n".join([
		"FPS: %d" % Engine.get_frames_per_second(),
		"Bullets: %d" % _child_count(bullet_root),
		"Enemies: %d" % _child_count(enemy_root),
		"SELayer: %d" % _child_count(se_layer),
		"Foreground: %d" % _child_count(foreground_layer),
		"Pool active/total: %d/%d" % [pool_stats["active"], pool_stats["total"]],
		"Pools: %d" % pool_stats["pool_count"],
		"Latency: off",
		"Net: off",
		"Top pools:",
		pool_stats["top_pools"],
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
