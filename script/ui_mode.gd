class_name UIMode
extends RefCounted

## 输入/UI 模式栈（唯一指针权威）。
##
## 主流做法：游戏内/菜单不各写 `Input.mouse_mode`，而是把"当前 UI 模式"作为唯一真源，
## 鼠标和准星都只是它的派生视图。任意时刻只有本类的 `apply()` 写鼠标模式：
##   GAMEPLAY  -> 鼠标隐藏、准星显示
##   MENU/UI   -> 鼠标显示、准星隐藏
##   CINEMATIC -> 鼠标隐藏、准星隐藏
##
## 场景根进入时设置基底（关卡 `enter_gameplay()`，主菜单 `enter_menu()`）；
## 全屏 UI 用 `bind_visibility(self)` 自动 push/pop；模态叠加时按栈顶生效。

enum Mode { GAMEPLAY, MENU, UI, CINEMATIC }

static var _base: int = Mode.GAMEPLAY
static var _entries: Array = []
static var _crosshair: Node = null


## UI 打开：压栈；同一 owner 重复 push 会更新模式并移到栈顶。
static func push(owner: Node, mode: int = Mode.UI) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	_prune()
	for i in range(_entries.size()):
		var entry: Dictionary = _entries[i]
		if entry.get("owner") == owner:
			entry["mode"] = mode
			_entries.remove_at(i)
			_entries.append(entry)
			apply()
			return
	_entries.append({"owner": owner, "mode": mode})
	apply()


## UI 关闭：移除 owner（未知 owner 直接忽略，不改变状态）。
static func pop(owner: Node) -> void:
	_prune()
	if owner != null:
		for i in range(_entries.size() - 1, -1, -1):
			var entry: Dictionary = _entries[i]
			if entry.get("owner") == owner:
				_entries.remove_at(i)
				break
	apply()


## 让一个全屏 UI 的显隐自动对应模式 push/pop；初始可见时补一次 push。
static func bind_visibility(node: Node, mode: int = Mode.UI) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.has_meta("ui_mode_bound"):
		return
	node.set_meta("ui_mode_bound", true)
	node.connect("visibility_changed", func() -> void:
		if is_instance_valid(node) and bool(node.get("visible")):
			push(node, mode)
		else:
			pop(node))
	node.tree_exiting.connect(func() -> void:
		pop(node))
	if bool(node.get("visible")):
		push(node, mode)


## 场景基底：关卡/测试房进入游戏模式；主菜单/选关进入菜单模式。
static func enter_gameplay() -> void:
	_base = Mode.GAMEPLAY
	_prune()
	apply()


static func enter_menu() -> void:
	_base = Mode.MENU
	_prune()
	apply()


## 准星只作为视图注册，不参与"谁该拿鼠标"的决策。
static func register_crosshair(node: Node) -> void:
	if node == null:
		return
	_crosshair = node
	apply()


static func unregister_crosshair(node: Node) -> void:
	if _crosshair == node:
		_crosshair = null
		apply()


static func effective_mode() -> int:
	_prune()
	if _entries.is_empty():
		return _base
	var entry: Dictionary = _entries[_entries.size() - 1]
	return int(entry.get("mode", Mode.UI))


static func is_gameplay() -> bool:
	return effective_mode() == Mode.GAMEPLAY


static func is_cursor_visible() -> bool:
	var mode := effective_mode()
	return mode == Mode.MENU or mode == Mode.UI


## 唯一写入点：把当前模式同步到系统鼠标和准星视图。
static func apply() -> void:
	_prune()
	var mode := effective_mode()
	var cursor_visible := mode == Mode.MENU or mode == Mode.UI
	var crosshair_visible := mode == Mode.GAMEPLAY
	var target_mouse := Input.MOUSE_MODE_VISIBLE if cursor_visible else Input.MOUSE_MODE_CONFINED_HIDDEN
	if Input.mouse_mode != target_mouse:
		Input.mouse_mode = target_mouse
	if _crosshair != null and is_instance_valid(_crosshair) and _crosshair.has_method("set_view_visible"):
		_crosshair.call("set_view_visible", crosshair_visible)


static func owner_count() -> int:
	_prune()
	return _entries.size()


## 调试快照：给 Game.input_debug_snapshot / 真机日志用。
static func debug_state() -> Dictionary:
	_prune()
	var entries: Array = []
	for entry in _entries:
		var owner = entry.get("owner")
		var owner_desc := ""
		if owner is Node and owner.is_inside_tree():
			owner_desc = str(owner.get_path())
		else:
			owner_desc = str(owner)
		entries.append({
			"owner": owner_desc,
			"mode": int(entry.get("mode", Mode.UI)),
		})
	var crosshair_desc := ""
	if _crosshair != null and is_instance_valid(_crosshair):
		crosshair_desc = str(_crosshair.get_path()) if _crosshair.is_inside_tree() else str(_crosshair)
	return {
		"base": _base,
		"mode": effective_mode(),
		"cursor_visible": is_cursor_visible(),
		"crosshair": crosshair_desc,
		"entries": entries,
	}


static func _prune() -> void:
	var alive: Array = []
	for entry in _entries:
		var owner = entry.get("owner")
		if owner != null and is_instance_valid(owner):
			alive.append(entry)
	_entries = alive
	if _crosshair != null and not is_instance_valid(_crosshair):
		_crosshair = null
