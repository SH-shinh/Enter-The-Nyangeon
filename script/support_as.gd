class_name SupportAS
extends Node2D

## 支援角色局内主动（EX）技能基类。
## 内聚：费用累积、EX_skill 输入、激活/结束守卫、GameEvents 发射、now_cost 归零。
## 子类覆写 _on_ready() / _on_skill_active() / _on_skill_end() 实现具体表现。

var as_is_active: bool = false
var emit_ready: bool = false

func _ready() -> void:
	GameEvents.round_upgrade.connect(skill_end)
	GameEvents.enemy_dead_score_owned.connect(_on_score_owned)
	_on_ready()

func _on_ready() -> void:
	pass

# 联机：远端镜像上的 SupportAS 不得参与本机支援逻辑（充能/输入/回合结束），
# 由 mod 在生成镜像时调用，避免镜像的"击杀充能"错误地累加本机 SupportData.now_cost。
func network_disable() -> void:
	if GameEvents.enemy_dead_score_owned.is_connected(_on_score_owned):
		GameEvents.enemy_dead_score_owned.disconnect(_on_score_owned)
	if GameEvents.round_upgrade.is_connected(skill_end):
		GameEvents.round_upgrade.disconnect(skill_end)
	set_process_unhandled_input(false)

# 击杀分归属门：只统计"归本机"的击杀（owner_peer=0 单机/本地；联机下等于本机 peer）。
# 联机时 host 会把客机归属的击杀转回客机本机发此信号，故各端只为自己击杀充能。
func _on_score_owned(_score: int, owner_peer: int) -> void:
	if owner_peer != 0 and owner_peer != multiplayer.get_unique_id():
		return
	cost_count(_score)

func cost_count(_score: int) -> void:
	if SupportData.now_cost < SupportData.ex_cost:
		SupportData.now_cost += 1
	elif not emit_ready:
		emit_ready = true
		GameEvents.emit_support_ex_ready()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("EX_skill") and SupportData.now_cost >= SupportData.ex_cost:
		skill_active()

func skill_active() -> void:
	if as_is_active:
		return
	as_is_active = true
	GameEvents.emit_support_ex_active()
	await _on_skill_active()

func skill_end() -> void:
	if not as_is_active:
		return
	as_is_active = false
	emit_ready = false
	SupportData.now_cost = 0
	_on_skill_end()
	GameEvents.emit_support_ex_end()

func _on_skill_active() -> void:
	pass

func _on_skill_end() -> void:
	pass
