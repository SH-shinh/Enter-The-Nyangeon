class_name UICursor
extends RefCounted

## 全屏 UI 的鼠标所有权（引用计数）。
##
## 游戏进行中鼠标是隐藏的（`scenes/crosshair/crosshair.gd` 负责），而全屏选单是
## CanvasLayer（layer 3/4+）→ 世界里的准星被盖住、系统指针又不可见，等于没有指针。
## 约定：UI 打开时 `show_for(self)`、关闭时 `hide_for(self)`；只有最后一个持有者释放时
## 才恢复到打开前的模式，所以调用先后顺序无关（关掉一个面板不会把另一个面板的鼠标藏回去）。
##
## `MOUSE_MODE_HIDDEN` 会被归一成 `MOUSE_MODE_CONFINED_HIDDEN`：`upgrade_manager` 在回合
## 结束时会把桌面端指针设成 `HIDDEN`，直接还原会丢掉"限制在窗口内"的语义。

const GAME_MODE := Input.MOUSE_MODE_CONFINED_HIDDEN

static var _owners: Array = []
static var _prev_mode: int = GAME_MODE


## UI 取得鼠标：首个持有者记录原模式，然后显示指针。
static func show_for(owner: Node) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	_prune()
	if _owners.has(owner):
		return
	if _owners.is_empty():
		_prev_mode = Input.mouse_mode
	_owners.append(owner)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## UI 释放鼠标：最后一个持有者释放时恢复原模式。
static func hide_for(owner: Node) -> void:
	if owner != null:
		_owners.erase(owner)
	_prune()
	if _owners.is_empty():
		Input.mouse_mode = normalize_mode(_prev_mode)


## 还原时的模式归一化：`HIDDEN` 视为游戏中的 `CONFINED_HIDDEN`。
static func normalize_mode(mode: int) -> int:
	if mode == Input.MOUSE_MODE_HIDDEN:
		return GAME_MODE
	return mode


## 调试/测试用：当前持有者数量。
static func owner_count() -> int:
	_prune()
	return _owners.size()


static func _prune() -> void:
	var alive := []
	for owner in _owners:
		if owner != null and is_instance_valid(owner):
			alive.append(owner)
	_owners = alive
