extends Control

## 触摸 UI 的输入态兜底。
##
## 引擎的 TouchScreenButton 只在 NOTIFICATION_PAUSED / EXIT_TREE 时释放自己，
## **不处理 Android 的 APPLICATION_FOCUS_OUT，也不处理 canceled 触摸**。失焦、切设备、
## 暂停或触屏 UI 被隐藏时若正按着 JUMP/MELEE/RELOAD/EX，finger_pressed 会卡住，
## 之后该按钮永久不响应。这里统一在隐藏/失焦/暂停/回合边界/模式切换时清理。
##
## 引擎没有公开的 release API：同帧把 visible 置 false 再置 true 会触发
## NOTIFICATION_VISIBILITY_CHANGED 内部的 _release()，且两次状态变更之间不会渲染，
## 不会产生闪烁。


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	Game.game_mode_changed.connect(_release_touch_state)
	GameEvents.round_start.connect(_release_touch_state)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		_release_touch_state()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_release_touch_state()


func _release_touch_state() -> void:
	for node in find_children("*", "TouchScreenButton", true, false):
		var button := node as TouchScreenButton
		if button == null:
			continue
		if button.action != StringName():
			Input.action_release(button.action)
		if button.is_pressed():
			button.visible = false
			button.visible = true
	# Knob / MouseKnob 的脚本态（finger_index、fire 按住等）也一并清掉。
	for node in find_children("*", "Node", true, false):
		if node.has_method("_release_all"):
			node.call("_release_all")
