@tool
extends McpTestSuite

## 回归：last_stand_component 的「成功」广播。
## 背景：buff 由「场景脚本」重构为 BuffComponent 后，旧 last_stand_buff.gd 的成功
## 广播 GameEvents.emit_player_buff_success 被漏掉，导致 tsurugi PS[1] 濒死复活后的
## 永久 +20% 子弹伤害 / +2 穿透从未生效。
## 现组件在非超时移除（回满血 / round_end / buff_clear）时 emit manager.buff_success，
## 由 PlayerBuffManager 转发到 GameEvents.player_buff_success。
##
## 编辑器 @tool 测试上下文里 autoload 是占位实例（脚本未以 tool 模式运行，属性读写/方法调用不可用），
## 故用子类覆写 _teardown() 隔离掉 autoload/body 清理，只驱动「成功 vs 超时」的广播与治疗分支。

const COMPONENT_SCRIPT := "res://resources/buff/components/last_stand_component.gd"
const LAST_STAND_BUFF := "res://resources/buff/player_buff/last_stand_buff.tres"


class TestComponent extends "res://resources/buff/components/last_stand_component.gd":
	func _teardown() -> void:
		pass


class FakeStats:
	signal hp_changed
	var max_hp: int = 100


class FakeHealth:
	var heal_data := HealData.new()
	var heal_calls: int = 0

	func take_damage(_d) -> void:
		heal_calls += 1


class FakeBody extends Node:
	var stats := FakeStats.new()
	var health_component := FakeHealth.new()


class FakeManager extends Node:
	signal buff_success(buff: Buff)


func suite_name() -> String:
	return "last_stand_success"


func _fresh(path: String) -> Resource:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func _make(buff: Buff) -> Dictionary:
	var comp = TestComponent.new()
	track(comp)
	var manager := FakeManager.new()
	track(manager)
	var body := FakeBody.new()
	track(body)
	comp.setup(manager, body)
	# 绕过 activate()（它重度依赖 autoload），直接置成「已激活」状态。
	comp.resource = buff
	comp.active = true
	comp.timed_out = false
	comp.first_life_num = 0
	return {"comp": comp, "manager": manager, "body": body}


func test_success_emits_buff_success_and_heals() -> void:
	var buff: Buff = _fresh(LAST_STAND_BUFF)
	var ctx := _make(buff)
	var got: Array = []
	ctx.manager.buff_success.connect(func(b): got.append(b))
	ctx.comp.deactivate()
	assert_eq(got.size(), 1, "非超时移除应广播一次 buff_success")
	assert_eq(got[0], buff, "payload 应为该 Buff 资源")
	assert_eq(ctx.body.health_component.heal_calls, 1, "成功应治疗一次")


func test_timeout_no_emit_no_heal() -> void:
	var buff: Buff = _fresh(LAST_STAND_BUFF)
	var ctx := _make(buff)
	ctx.comp.timed_out = true
	var got: Array = []
	ctx.manager.buff_success.connect(func(b): got.append(b))
	ctx.comp.deactivate()
	assert_eq(got.size(), 0, "超时应不广播 buff_success")
	assert_eq(ctx.body.health_component.heal_calls, 0, "超时应不治疗")
