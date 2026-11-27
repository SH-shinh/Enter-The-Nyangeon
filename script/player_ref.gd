class_name PlayerRef

# 本地玩家引用工具。
#
# 玩家节点会在运行期被销毁重建（换角色：ui/test_character_card.gd、ui/test_menu.gd、
# ui/character_test_menu.gd 的 free + re-add；测试房重置等）。池化节点（子弹/敌弹/敌人/
# 特效）与长生命周期节点（召唤物、场景物件、管理器）若只在 _ready()/_on_equip() 里缓存
# 一份 player 就长期复用，玩家重建后就会拿着已释放实例取属性，报
# `Invalid access to property or key 'xxx' on a base object of type 'previously freed'`。
# 取用前统一走 resolve() / ensure()，不要直接读旧缓存。

# 取当前有效的本地玩家；from 不在树内、场上暂无玩家时返回 null。
static func resolve(from: Node) -> Node:
	if from == null or not is_instance_valid(from) or not from.is_inside_tree():
		return null
	var tree := from.get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("Player")

# cached 仍有效则原样返回；为空或已释放时重新解析。调用方应把返回值写回缓存成员。
#
# cached 故意声明为 Variant 而非 Node：传入**已释放实例**时，Godot 会在进入函数前的
# 入参类型检查就抛 "The Object-derived class of argument 2 (previously freed) is not a
# subclass of the expected argument class."，导致 is_instance_valid 根本执行不到。改用
# 弱类型入参 + 运行时 is_instance_valid 判定，才能真正做到"失效即重新解析"。
static func ensure(from: Node, cached: Variant) -> Node:
	# 先 `is_instance_valid`（对已释放实例安全），再判类型：若写成 `cached is Node` 在前，
	# 传入已释放实例时会在该处抛 "Left operand of 'is' is a previously freed instance."，
	# 函数体内的判定根本执行不到。
	if is_instance_valid(cached) and cached is Node and cached.is_inside_tree():
		return cached as Node
	return resolve(from)


## 按 process 帧缓存的解析：同一帧内的批量热点（如 buff 施加/结算里每帧上千次
## `_ensure_player`）只查一次组；null 也缓存（同一帧内不会换人）。
## 跨帧令牌用 `Engine.get_process_frames()`，换角色/重载玩家最迟下一帧生效。
static var _frame_token: int = -1
static var _frame_player: Node = null

static func resolve_cached(from: Node) -> Node:
	var frame := Engine.get_process_frames()
	if frame == _frame_token:
		return _frame_player
	_frame_token = frame
	_frame_player = resolve(from)
	return _frame_player
