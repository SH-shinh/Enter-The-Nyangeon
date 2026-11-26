class_name UICursor
extends RefCounted

## 旧 UI 的兼容门面：本体新代码请直接用 UIMode。
## 这里仍提供 show_for/hide_for/owner_count，方便 mod 与旧测试平滑过渡；
## 鼠标/准星的真正决策全部在 UIMode 的模式栈里。

const GAME_MODE := Input.MOUSE_MODE_CONFINED_HIDDEN


## UI 取得鼠标：等价于压入 UI 模式。
static func show_for(owner: Node) -> void:
	UIMode.push(owner, UIMode.Mode.UI)


## UI 释放鼠标：等价于弹出该 owner 的 UI 模式。
static func hide_for(owner: Node) -> void:
	UIMode.pop(owner)


static func owner_count() -> int:
	return UIMode.owner_count()


## 旧测试/旧调用仍可能用到的归一化：HIDDEN 视为游戏中的 CONFINED_HIDDEN。
static func normalize_mode(mode: int) -> int:
	if mode == Input.MOUSE_MODE_HIDDEN:
		return GAME_MODE
	return mode
