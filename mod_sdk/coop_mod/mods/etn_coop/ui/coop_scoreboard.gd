extends CanvasLayer

## CoopScoreboard：联机实时战绩面板（按住 coop_scoreboard 键，默认 Tab，显示）。
## 静态布局在 coop_scoreboard.tscn / coop_scoreboard_row.tscn（可在编辑器手动调整）；
## 本脚本只负责：注册输入、按数据实例化行、填文本。数据来自 CoopNet.team_stats（host 周期广播）。
## mod 内不使用 class_name。

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const RowScene := preload("res://mods/etn_coop/ui/coop_scoreboard_row.tscn")
const ACTION := "coop_scoreboard"
const CHAT_GAP: float = 6.0  # 战绩栏与聊天窗之间的最小间隙(px)

# 击杀/金币的缩写阈值：低于阈值显示完整数字，达到/超过才用 K/M/B/T。
# 按列宽估算（击杀列 60px、金币列 70px，BoutiqueBitmap9x9 @ font_size 8 数字约 4.8px/位）。
const KILLS_ABBREV_AT := 100000
const COINS_ABBREV_AT := 1000000

@onready var _rows: VBoxContainer = %Rows
@onready var _center: Control = $Center
@onready var _panel: PanelContainer = $Center/Panel

var _sig: String = ""
var _chat: Node = null
var _mobile: bool = OS.has_feature("mobile")


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
	var active: bool = coop != null and is_instance_valid(coop) and bool(coop.is_lan_game)
	var show: bool = false
	if active:
		if Input.is_action_pressed(ACTION):
			show = true
		elif _mobile:
			# 移动端无 coop_scoreboard 按键：点开聊天（输入态）时一起显示战绩。
			var chat := _get_chat()
			show = chat != null and bool(chat.call("is_composing"))
	if visible != show:
		visible = show
	if show:
		_refresh(coop)
		_apply_chat_offset()
	else:
		offset = Vector2.ZERO


func _get_chat() -> Node:
	if _chat == null or not is_instance_valid(_chat):
		_chat = get_tree().root.get_node_or_null("CoopChat")
	return _chat


# 聊天窗显示时整层左移，使战绩面板右缘不遮挡聊天窗左缘（双端生效）。
# 移动距离按两者实际尺寸算：未偏移时面板右缘 - 聊天窗左缘 + 间隙。
func _apply_chat_offset() -> void:
	var chat := _get_chat()
	if chat == null or not bool(chat.call("is_window_visible")):
		offset = Vector2.ZERO
		return
	# 用布局尺寸推未偏移右缘，避免读取受 offset 影响的位置导致反馈增长。
	var unshifted_right: float = _center.size.x * 0.5 + _panel.size.x * 0.5
	var crect: Rect2 = chat.call("get_window_rect")
	offset = Vector2(-maxf(0.0, unshifted_right + CHAT_GAP - crect.position.x), 0.0)


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
		_set_text(row, "%Kills", _fmt_num(int(d.get("kills", 0)), KILLS_ABBREV_AT))
		_set_text(row, "%Damage", _fmt_num(int(d.get("damage", 0))))
		_set_text(row, "%Coins", _fmt_num(int(d.get("coins", 0)), COINS_ABBREV_AT))


func _set_text(row: Node, unique_path: String, value: String) -> void:
	var n = row.get_node_or_null(unique_path)
	if n != null and n is Label:
		(n as Label).text = value


# 大数缩写：<abbrev_at 原样；否则 K/M/B/T（1 位小数、去尾随 .0，含进位保护）
# 默认阈值 1000（伤害沿用）；击杀/金币传入更高阈值。
static func _fmt_num(n: int, abbrev_at: int = 1000) -> String:
	if n < 0:
		n = 0
	if n < abbrev_at:
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
