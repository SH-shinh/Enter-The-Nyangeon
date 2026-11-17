class_name BackstabPassive
extends Node

# 角色/道具级背刺被动：监听前置伤害阶段，对近战、投射物、装备直伤追加背刺倍率。
# 普通倍率从 owner 的 stats.backstab_damage 读取，角色级 bonus 再叠加。
# 爆炸、DOT、真伤默认不触发；近战触发与否由 damage_type 决定，不需要逐个道具改。
# 挂到玩家/角色上覆盖其全部合格伤害；只给某件道具时，直接在该道具的 DamageData
# 上 append 一个调用 Backstab.boost 的 modifier，不要挂本组件（否则会覆盖全角色）。

## 角色/道具级额外背刺倍率；实际普通背刺读取玩家 stats.backstab_damage，再加这个 bonus。
@export var bonus: float = 0.0
## 只接受这些来源标签；默认玩家枪弹、PS、装备。召唤物/策反需要时自行追加。
@export var source_tags: Array[String] = [GameTags.PLAYER, GameTags.PS_DAMAGE, GameTags.EQUIP]
## 非空时还要求伤害类型命中其一；空 = 除黑名单外全收。
@export var allowed_damage_types: Array[String] = []

## 幂等挂载：已有 BackstabPassive 子节点时只更新配置。
static func attach(owner: Node, cfg: Dictionary = {}) -> BackstabPassive:
	if owner == null or not is_instance_valid(owner):
		return null
	for child in owner.get_children():
		if child is BackstabPassive and not child.is_queued_for_deletion():
			child.configure(cfg)
			return child
	var passive := BackstabPassive.new()
	passive.name = "BackstabPassive"
	owner.add_child(passive)
	passive.configure(cfg)
	return passive

func _ready() -> void:
	if not GameEvents.enemy_damage_calculating.is_connected(_on_damage_calculating):
		GameEvents.enemy_damage_calculating.connect(_on_damage_calculating)

func _exit_tree() -> void:
	if GameEvents.enemy_damage_calculating.is_connected(_on_damage_calculating):
		GameEvents.enemy_damage_calculating.disconnect(_on_damage_calculating)

func configure(cfg: Dictionary) -> void:
	if cfg.has("bonus"):
		bonus = maxf(0.0, float(cfg["bonus"]))
	if cfg.has("source_tags"):
		source_tags.assign(cfg["source_tags"])
	if cfg.has("allowed_damage_types"):
		allowed_damage_types.assign(cfg["allowed_damage_types"])

## 本次伤害是否属于背刺可结算范围。
func accepts(data: DamageData) -> bool:
	if data == null or data.is_heal:
		return false
	if data.source_type.is_empty() or data.damage_type.is_empty():
		return false
	if Faction.of_source(data.source_type) != Faction.PLAYER_SIDE:
		return false
	if not source_tags.is_empty() and not _has_any(data.source_type, source_tags):
		return false
	# 爆炸、持续伤害不触发；真伤不走 modifier，这里显式挡掉避免误以为支持。
	if data.damage_type.has(GameTags.EXPLOSION_DAMAGE):
		return false
	if data.damage_type.has(GameTags.DOT_DAMAGE):
		return false
	if data.flags.has(GameTags.TRUE_DAMAGE):
		return false
	if not allowed_damage_types.is_empty() and not _has_any(data.damage_type, allowed_damage_types):
		return false
	# 未入树时（单测/预配置）没有 multiplayer 实例，跳过 peer 过滤；游戏内正常走本机判定。
	if is_inside_tree():
		var mp: MultiplayerAPI = multiplayer
		if mp != null:
			var peer: MultiplayerPeer = mp.multiplayer_peer
			if peer != null:
				var owner_peer := int(data.owner_peer)
				if owner_peer != 0 and owner_peer != mp.get_unique_id():
					return false
	return true

func _on_damage_calculating(_final_damage: int, data: DamageData, _body_path: NodePath) -> void:
	if data != null:
		# 共享 DamageData（scythe/火场等）按目标结算：每个目标先清 Weak，再决定是否追加。
		data.flags.erase(GameTags.WEAK_DAMAGE)
	if not accepts(data):
		return
	var cb := Callable(self, "_modify").bind(data)
	if not data.damage_modifier.has(cb):
		data.damage_modifier.append(cb)

func _modify(victim: Node, amount: int, data: DamageData) -> int:
	if victim == null or not is_instance_valid(victim):
		return amount
	if not (victim is Enemy or victim is EnemyPart):
		return amount
	if not Backstab.is_back(victim):
		return amount
	if data != null and not data.flags.has(GameTags.WEAK_DAMAGE):
		data.flags.append(GameTags.WEAK_DAMAGE)
	var base_mult := Backstab.DEFAULT_MULT
	var owner := get_parent()
	if owner != null and is_instance_valid(owner):
		var stats = owner.get("stats")
		if stats != null and stats.get("backstab_damage") != null:
			base_mult = maxf(1.0, float(stats.backstab_damage))
	var total_mult := maxf(1.0, base_mult + bonus)
	return Backstab.boost(victim, amount, total_mult)

func _has_any(values: Array, wanted: Array) -> bool:
	for value in wanted:
		if values.has(value):
			return true
	return false
