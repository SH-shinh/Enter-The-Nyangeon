class_name ShockEquipItem
extends EquipItem

# 感电系道具基类：统一「施加感电」与「短弧表现」两个出口，避免各道具重复拼装。
#
# 施加必须走 enemy_buff_manager.apply_buff(...)：联机客机会被 mod 拦下转发房主权威应用，
# 房主应用后再广播回来，两端层数才一致（见 mods/etn_coop 的 _gate_enemy_buff_apply）。
# 层上限/伤害/时长都取「施加者」属性（applier_stats），所以必须带上 player 的快照。
#
# 链本身的视觉由 ShockChain 的 on_shock_chain 统一广播；这里的短弧只是本机表现，
# 与 chihiro 无人机放电的做法一致，不单独广播，避免逐次命中刷网络。

const SHOCK_BUFF: Buff = preload("res://resources/buff/enemy_buff/shock_dot.tres")
const SHOCK_ID: String = "shock_dot"
const ARC_SCENE: PackedScene = preload("res://scenes/debuff/shock_chain_arc.tscn")
const ARC_POOL: String = "shock_chain"
## 施加时写进 value[2] 的时长占位：感电实际时长由 enemy_buff_manager 用 40 tick × dot_time 覆盖。
const SHOCK_VALUE_TIME: float = 4.0

## 施加者属性快照（层上限 / 异常伤害 / 持续时间 / 全局伤害）。仅本类内部使用。
func _shock_applier_stats() -> Dictionary:
	var st = player.stats if player != null else null
	if st == null:
		return {}
	return {
		"shock_layer": int(st.shock_layer),
		"dot_damage": float(st.dot_damage),
		"dot_time": float(st.dot_time),
		"global_damage": float(st.global_damage),
	}

## 命中点 → 敌人本体：直接命中的敌人/护盾自带 enemy_buff_manager；
## 若将来出现挂在敌人下的子部件，向上最多找 3 层兜底。
func resolve_enemy_body(node) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if node.get("enemy_buff_manager") != null:
		return node
	var parent: Node = node.get_parent()
	for _i in 3:
		if parent == null or not is_instance_valid(parent):
			return null
		if parent.get("enemy_buff_manager") != null:
			return parent
		parent = parent.get_parent()
	return null

## 目标当前感电层数；无该状态返回 0。
func shock_layer_of(body) -> int:
	if body == null or not is_instance_valid(body):
		return 0
	var manager = body.get("enemy_buff_manager")
	if manager == null:
		return 0
	var cbs = manager.get("current_buff")
	if not (cbs is Dictionary):
		return 0
	var entry = cbs.get(SHOCK_ID)
	if not (entry is Dictionary):
		return 0
	if bool(entry.get("stop", false)):
		return 0
	return maxi(0, int(entry.get("layer", 0)))

## 给目标叠加 layers 层感电，返回实际增加的层数（打满层上限后为 0）。
func apply_shock(body, layers: int = 1) -> int:
	if layers <= 0 or body == null or not is_instance_valid(body):
		return 0
	if body.get("is_idle") == 1:
		return 0
	var st = body.get("stats")
	if st != null and int(st.get("hp")) <= 0 and not bool(st.get("is_test_target")):
		return 0
	var manager = body.get("enemy_buff_manager")
	if manager == null:
		return 0
	var before := shock_layer_of(body)
	var applier := _shock_applier_stats()
	var cap: int = int(applier.get("shock_layer", 1))
	for _i in layers:
		manager.apply_buff(SHOCK_BUFF, [cap, 0.0, SHOCK_VALUE_TIME], item_id, applier)
	return maxi(0, shock_layer_of(body) - before)

## 本机表现的短弧（起点通常是玩家，终点自动抬到敌人胸口高度）。
func spawn_shock_arc(from: Vector2, to: Vector2, power: int = 3) -> void:
	if not PoolManager.fx_allowed(&"shock_chain"):
		return
	var layer := get_tree().get_first_node_in_group("SELayer")
	if layer == null:
		return
	var fx = PoolManager.get_pool(ARC_POOL)
	if fx == null or fx.is_idle == 0:
		fx = ARC_SCENE.instantiate()
		layer.add_child(fx)
	fx.play([from, to + Vector2(0, -12)], power)

## 玩家胸口高度：多数道具的弧起点。
func player_center() -> Vector2:
	if player == null:
		return Vector2.ZERO
	return player.global_position + Vector2(0, -12)
