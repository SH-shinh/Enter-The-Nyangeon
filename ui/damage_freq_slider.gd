extends HSlider

## 伤害数字频率滑条：同时兼容桌面鼠标与触屏。
## 桌面鼠标由 HSlider 原生处理（project 关闭了 emulate_mouse_from_touch，
## 故触屏需自行把触摸 x 比例映射到最近档位）。逻辑写入留在 option.gd。

func _ready() -> void:
	gui_input.connect(_on_gui_input)

func _on_gui_input(event: InputEvent) -> void:
	if size.x <= 0.0:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_apply_touch(event.position.x)
	elif event is InputEventScreenDrag:
		_apply_touch(event.position.x)

func _apply_touch(local_x: float) -> void:
	var frac: float = clampf(local_x / size.x, 0.0, 1.0)
	value = roundf(frac * max_value)
