extends CanvasLayer

## 「已就绪」遮罩：半透明黑底 + 居中白字。ESC 取消就绪。
## 全员就绪后（waiting=true）锁定 ESC，文字改为「等待房主选择」。
## 静态布局在 coop_ready.tscn；本脚本只切文字/锁定。

signal cancel_ready

@onready var _label: Label = %ReadyLabel
@onready var _hint: Label = %Hint

var _waiting: bool = false


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
