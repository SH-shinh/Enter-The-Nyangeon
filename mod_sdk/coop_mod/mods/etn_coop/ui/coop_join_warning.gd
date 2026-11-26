extends ConfirmationDialog

## 加入房间时的 mod 不一致警告：进入 / 退出（不阻止进入）。
## 由 CoopNet 在握手接纳后创建；常驻节点，process_mode = ALWAYS 保证暂停时也能操作。

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	exclusive = true
	dialog_autowrap = true
	min_size = Vector2i(560, 240)


func setup(title_text: String, body_text: String, ok_text: String, cancel_text: String) -> void:
	title = title_text
	dialog_text = body_text
	ok_button_text = ok_text
	cancel_button_text = cancel_text
	popup_centered()
