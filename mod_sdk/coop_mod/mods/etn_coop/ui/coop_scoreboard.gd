extends CanvasLayer

## CoopScoreboard：联机实时战绩面板（按住 coop_scoreboard 键，默认 Tab，显示）。
## 静态布局在 coop_scoreboard.tscn / coop_scoreboard_row.tscn（可在编辑器手动调整）；
## 本脚本只负责：注册输入、按数据实例化行、填文本。数据来自 CoopNet.team_stats（host 周期广播）。
## mod 内不使用 class_name。

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const RowScene := preload("res://mods/etn_coop/ui/coop_scoreboard_row.tscn")
const ACTION := "coop_scoreboard"

@onready var _rows: VBoxContainer = %Rows

var _sig: String = ""


func _ready() -> void:
	if not InputMap.has_action(ACTION):
		InputMap.add_action(ACTION)
		var key := InputEventKey.new()
		key.physical_keycode = KEY_TAB
		InputMap.action_add_event(ACTION, key)
		var jb := InputEventJoypadButton.new()
		jb.button_index = JOY_BUTTON_BACK
		InputMap.action_add_event(ACTION, jb)
	visible = false


func _process(_delta: float) -> void:
	var coop = CoopNetScript.instance
	var show: bool = Input.is_action_pressed(ACTION) \
			and coop != null and is_instance_valid(coop) and bool(coop.is_lan_game)
	if visible != show:
		visible = show
	if show:
		_refresh(coop)


func _refresh(coop) -> void:
	var stats: Dictionary = coop.get("team_stats")
	if str(stats) == _sig:
		return
	_sig = str(stats)
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	var pids: Array = stats.keys()
	pids.sort_custom(func(a, b): return int(stats[a].get("damage", 0)) > int(stats[b].get("damage", 0)))
	for pid in pids:
		var d = stats[pid]
		if not (d is Dictionary):
			continue
		var row = RowScene.instantiate()
		_rows.add_child(row)
		_set_text(row, "%Name", str(coop.call("_display_name_for", int(pid))))
		_set_text(row, "%Kills", _fmt_num(int(d.get("kills", 0))))
		_set_text(row, "%Damage", _fmt_num(int(d.get("damage", 0))))
		_set_text(row, "%Coins", _fmt_num(int(d.get("coins", 0))))


func _set_text(row: Node, unique_path: String, value: String) -> void:
	var n = row.get_node_or_null(unique_path)
	if n != null and n is Label:
		(n as Label).text = value


# 大数缩写：<1000 原样；否则 K/M/B/T（1 位小数、去尾随 .0，含进位保护）
static func _fmt_num(n: int) -> String:
	if n < 0:
		n = 0
	if n < 1000:
		return str(n)
	var units: Array[String] = ["K", "M", "B", "T"]
	var v: float = float(n)
	var idx: int = -1
	while v >= 1000.0 and idx < units.size() - 1:
		v /= 1000.0
		idx += 1
	var s: String = _trim_decimal(v)
	if s.to_float() >= 1000.0 and idx < units.size() - 1:
		v /= 1000.0
		idx += 1
		s = _trim_decimal(v)
	return s + units[idx]


static func _trim_decimal(v: float) -> String:
	var s: String = "%.1f" % v
	if s.ends_with(".0"):
		s = s.substr(0, s.length() - 2)
	return s
