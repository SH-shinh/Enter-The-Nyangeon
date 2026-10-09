@tool
extends McpTestSuite

## 回归：PoolManager 取池语义。
## 关键不变式：
##  - 存在空闲节点时绝不强收活跃节点（旧实现会无条件 idle_state() 掉活跃节点）。
##  - 无空闲且未达上限返回 null（调用方新建），满额才静默回收轮转槽位。
##  - get_pool_idle 永不强收（金币等自管计数池依赖）。
##  - detach / tree_exiting 从池内移除。
## 用独立实例（不入树，不触发 _ready 的 GameEvents 连接）隔离测试。

const POOL_SCRIPT := "res://scenes/manager/PoolManager.gd"


class PoolNode extends Node:
	var is_idle: int = 1
	var idle_calls: int = 0
	var silent_calls: int = 0

	func idle_state() -> void:
		is_idle = 1
		idle_calls += 1

	func active_state() -> void:
		is_idle = 0

	func deactivate_silent() -> void:
		is_idle = 1
		silent_calls += 1


var _pm: Node = null


func suite_name() -> String:
	return "pool_manager"


func setup() -> void:
	# CACHE_MODE_IGNORE：绕过 GDScript preload 缓存，确保测的是磁盘上的最新脚本。
	_pm = ResourceLoader.load(POOL_SCRIPT, "", ResourceLoader.CACHE_MODE_IGNORE).new()
	track(_pm)


func _node() -> Node:
	var n := PoolNode.new()
	track(n)
	return n


func test_empty_pool_returns_null() -> void:
	assert_true(_pm.get_pool("nothing") == null, "空池 get_pool 应为 null")
	assert_true(_pm.get_pool_idle("nothing") == null, "空池 get_pool_idle 应为 null")


func test_get_returns_distinct_idle() -> void:
	for i in 3:
		_pm.add_pool("t", _node())
	var a: Node = _pm.get_pool("t")
	var b: Node = _pm.get_pool("t")
	var c: Node = _pm.get_pool("t")
	assert_true(a != null and b != null and c != null, "空闲充足时三次取池均应有返回")
	assert_true(a != b and b != c and a != c, "多次取池应返回不同节点")
	assert_eq(a.is_idle, 1, "get_pool 取用不改 idle 状态（由调用方激活）")


func test_no_idle_under_cap_returns_null() -> void:
	var a := _node()
	var b := _node()
	_pm.add_pool("stone_bullet", a)  # limit=40
	_pm.add_pool("stone_bullet", b)
	a.active_state()
	b.active_state()
	assert_true(_pm.get_pool("stone_bullet") == null, "未达上限且无空闲应返回 null（调用方新建）")
	assert_eq(a.idle_calls, 0, "不得强收活跃节点")
	assert_eq(b.idle_calls, 0, "不得强收活跃节点")


func test_no_cap_pool_all_busy_returns_null() -> void:
	var a := _node()
	_pm.add_pool("uncapped_test", a)  # 不在 IDLE_LIMITS -> limit=-1
	a.active_state()
	assert_true(_pm.get_pool("uncapped_test") == null, "无上限池全忙应返回 null")


func test_get_pool_idle_never_forces() -> void:
	var a := _node()
	var b := _node()
	_pm.add_pool("player_laser_bullet", a)  # limit=1
	_pm.add_pool("player_laser_bullet", b)
	a.active_state()
	b.active_state()
	assert_true(_pm.get_pool_idle("player_laser_bullet") == null, "get_pool_idle 不应强收")
	assert_eq(a.idle_calls, 0, "get_pool_idle 不得回收活跃节点")


func test_at_cap_silently_recycles() -> void:
	var a := _node()
	_pm.add_pool("player_laser_bullet", a)  # limit=1
	a.active_state()
	var got: Node = _pm.get_pool("player_laser_bullet")
	assert_true(got == a, "满额全忙应回收并返回该槽位")
	assert_eq(a.is_idle, 1, "回收后应为空闲态")
	assert_eq(a.silent_calls, 1, "应走 deactivate_silent 静默回收")
	assert_eq(a.idle_calls, 0, "满额回收不应触发带副作用的 idle_state")


func test_idle_preferred_over_active_at_over_cap() -> void:
	var active := _node()
	var idle := _node()
	_pm.add_pool("player_laser_bullet", active)  # limit=1
	_pm.add_pool("player_laser_bullet", idle)    # body.size=2 > limit
	active.active_state()
	# idle 保持 is_idle=1
	var got: Node = _pm.get_pool("player_laser_bullet")
	assert_true(got == idle, "存在空闲时必须优先返回空闲节点")
	assert_eq(active.idle_calls, 0, "不得强收活跃节点")
	assert_eq(active.silent_calls, 0, "不得静默回收活跃节点")


func test_detach_removes_from_pool() -> void:
	var a := _node()
	_pm.add_pool("t", a)
	_pm.detach(a)
	assert_eq(_pm.pool_total("t"), 0, "detach 后池内应移除")
	assert_true(_pm.get_pool("t") == null, "detach 后取池应为 null")


func test_tree_exiting_removes_from_pool() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		skip("无 SceneTree.root")
		return
	var a := _node()
	tree.root.add_child(a)
	_pm.add_pool("t", a)
	assert_eq(_pm.pool_total("t"), 1, "注册后池内应有该节点")
	tree.root.remove_child(a)
	assert_eq(_pm.pool_total("t"), 0, "tree_exiting 后应自注销")


func test_stats_counts() -> void:
	var a := _node()
	var b := _node()
	_pm.add_pool("stone_bullet", a)
	_pm.add_pool("stone_bullet", b)
	b.active_state()
	assert_eq(_pm.pool_total("stone_bullet"), 2, "总数")
	assert_eq(_pm.pool_idle_count("stone_bullet"), 1, "空闲数")
	assert_eq(_pm.pool_active_count("stone_bullet"), 1, "活跃数")
	var stats: Dictionary = _pm.pool_stats()
	assert_has_key(stats, "stone_bullet", "pool_stats 应含该池")
