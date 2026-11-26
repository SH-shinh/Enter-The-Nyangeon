extends CanvasLayer

## 「已就绪」遮罩：半透明黑底 + 居中白字。ESC 取消就绪。
## 全员就绪后（waiting=true）锁定 ESC，文字改为「等待房主选择」。
## 静态布局在 coop_ready.tscn；本脚本只切文字/锁定。

signal cancel_ready

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")

@onready var _label: Label = %ReadyLabel
@onready var _hint: Label = %Hint

var _waiting: bool = false


func _ready() -> void:
	_refresh_selection_hint()


# 就绪界面回显"你已选择：<角色>"：让玩家在开战前一眼确认角色没选错
func _refresh_selection_hint() -> void:
	if _hint == null:
		return
	var name: String = ""
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop) and coop.has_method("get_selected_character_name"):
		name = str(coop.call("get_selected_character_name"))
	var base: String = tr("coop_cancel_ready_hint") if tr("coop_cancel_ready_hint") != "coop_cancel_ready_hint" else ""
	if name != "":
		_hint.text = (tr("coop_selected_character") % name) + ("\n" + base if base != "" else "")
		_hint.visible = true


func set_waiting() -> void:
	_waiting = true
	if _label != null:
		_label.text = tr("coop_waiting_host")
	if _hint != null:
		_hint.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _waiting:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		cancel_ready.emit()
		get_viewport().set_input_as_handled()
