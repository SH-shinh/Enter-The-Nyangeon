extends CanvasLayer

## 回合升级「等待所有人就绪」遮罩：半透明黑底 + 居中大字。
## 纯展示：不注册任何取消/返回输入（ESC 无效）。由 CoopFlow 打开/关闭，
## 挂在当前场景下，切场景自动释放。

@onready var _label: Label = %ReadyLabel


func _ready() -> void:
	if _label != null:
		_label.text = tr("coop_wait_all_ready")
