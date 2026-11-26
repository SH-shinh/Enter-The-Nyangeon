extends EquipItem

# 能量饼干：按存活召唤物数量 × 持有件数档位提高召唤物伤害。
# 召唤物计入数量无上限（2026-11-20 用户裁定，原为最多 5 个）。
#
# 落点写 PlayerData.summoned_damage_add（1.0 = 100% 乘区），由 SummonedManager
# 批量刷新到各召唤物 stats.summoned_damage_mult；该乘区同时作用于策反单位
# （DamageRouter.converted_damage），属既有设计。
#
# 记账必须走「差值」并监听 PlayerData.reset_done：reset_date() 会把
# summoned_damage_add 清零，若不归零本地记账，下一次刷新会把它减成负数。

## 持有 1/2/3/4/5 件时，每个计入的召唤物提供的加成（累计数量取档，不乘 quantity）。
const PER_SUMMON_BY_QUANTITY: Array[float] = [0.15, 0.20, 0.25, 0.30, 0.35]

var _per_summon: float = PER_SUMMON_BY_QUANTITY[0]
var _applied_delta: float = 0.0
var _summoned_manager: Node

func _on_equip() -> void:
	_summoned_manager = get_tree().get_first_node_in_group("SummonedManager")

func _setup() -> void:
	if _summoned_manager != null and is_instance_valid(_summoned_manager):
		if not _summoned_manager.summoned_changed.is_connected(_refresh):
			_summoned_manager.summoned_changed.connect(_refresh)
	if not PlayerData.reset_done.is_connected(_on_player_reset):
		PlayerData.reset_done.connect(_on_player_reset)
	_refresh()

func _apply_effect(quantity: int) -> void:
	_per_summon = PER_SUMMON_BY_QUANTITY[clampi(quantity, 1, PER_SUMMON_BY_QUANTITY.size()) - 1]
	_refresh()

func _refresh() -> void:
	if _summoned_manager == null or not is_instance_valid(_summoned_manager):
		return
	if not _player_ready():
		return
	var target: float = float(_count_summoned()) * _per_summon
	if is_equal_approx(target, _applied_delta):
		return
	PlayerData.summoned_damage_add += target - _applied_delta
	_applied_delta = target
	PlayerData.update_player_ability()

func _count_summoned() -> int:
	var group = _summoned_manager.get("summoned_group")
	if not (group is Array):
		return 0
	var count: int = 0
	for summon in group:
		if summon == null or not is_instance_valid(summon) or summon.is_queued_for_deletion():
			continue
		if int(summon.get("is_idle")) != 0:
			continue
		# 联机镜像不计入：只有本机拥有的召唤物才吃本机道具。
		if summon.has_meta("remote_summoned"):
			continue
		if summon.has_meta("is_local_summoned") and not bool(summon.get_meta("is_local_summoned")):
			continue
		count += 1
	return count

func _on_player_reset() -> void:
	# reset_date() 已把 summoned_damage_add 归零，丢弃本地记账，避免下次减成负数。
	_applied_delta = 0.0
	# 测试房重置只清部分节点、本道具仍挂在玩家下；本局已不再记录它时自清理，
	# 避免旧节点在新一轮继续加算（并与重新抽到的新节点叠加）。
	if item_id != "" and not PlayerData.current_upgrades.has(item_id):
		queue_free()

func _exit_tree() -> void:
	super._exit_tree()
	if item_id == "" or _applied_delta == 0.0:
		return
	# 只在「仍记为本局道具」且玩家仍有效时回滚；重置/清档后账本已被清零，不能再减。
	if PlayerData.current_upgrades.has(item_id) and _player_ready():
		PlayerData.summoned_damage_add -= _applied_delta
		PlayerData.update_player_ability()
	_applied_delta = 0.0

func _player_ready() -> bool:
	var current_player = PlayerData.player
	return current_player != null and is_instance_valid(current_player) \
		and current_player.get("stats") != null
