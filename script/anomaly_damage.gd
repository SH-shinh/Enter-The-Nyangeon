class_name AnomalyDamage
extends RefCounted

# Maki 被动「异常伤害可暴击」的统一判定与掷骰。
#
# 生效范围是「本机玩家带 Maki 被动」时的所有异常类伤害：燃烧/中毒/恶寒的 DOT 跳伤、
# 恶寒反击、火场/火伤圈/毒环等纯元素直伤。子弹/近战/爆炸/策反已在各自流程掷暴击
# （且会与元素标签并存），因此这里用「排除复合标签」避免双重暴击。
#
# 判定放在 HealthComponent._resolve_damage() 的最终数值口，调用方无需逐个改脚本；
# 共享 DamageData（火场/毒环一次激活多目标、跨 tick 复用）由调用方每次结算前复位 is_crit。

## 本机玩家节点上的被动标记：由 MakiPS 在本地 _ready 置位；联机镜像玩家不置。
const META_PASSIVE: String = "anomaly_damage_can_crit"


## 本机玩家是否带「异常伤害可暴击」被动。
static func passive_enabled(player: Node) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	return bool(player.get_meta(META_PASSIVE, false))


## 是否为核心异常类伤害：带元素/DOT 标签，且不含子弹/近战/爆炸等复合标签。
static func is_anomaly_damage(data: DamageData) -> bool:
	if data == null:
		return false
	if data.damage_type.has(GameTags.BULLET_DAMAGE) \
			or data.damage_type.has(GameTags.MELEE_DAMAGE) \
			or data.damage_type.has(GameTags.EXPLOSION_DAMAGE) \
			or data.damage_type.has(GameTags.CRIT_DAMAGE):
		return false
	return data.damage_type.has(GameTags.FIRE_DAMAGE) \
			or data.damage_type.has(GameTags.POISON_DAMAGE) \
			or data.damage_type.has(GameTags.CHILL_DAMAGE) \
			or data.damage_type.has(GameTags.DOT_DAMAGE)


## 是否允许本次异常伤害掷暴击：被动开 + 玩家侧来源 + 纯异常类。
static func can_roll(player: Node, data: DamageData) -> bool:
	if not passive_enabled(player):
		return false
	if data == null:
		return false
	if Faction.of_source(data.source_type) != Faction.PLAYER_SIDE:
		return false
	return is_anomaly_damage(data)


## 掷一次暴击，返回伤害乘区（1.0 = 不暴击）。必暴阈值与玩家子弹一致（< critical_luck）。
static func roll_crit(player: Node) -> float:
	if player == null or not is_instance_valid(player):
		return 1.0
	var stats = player.get("stats")
	if stats == null:
		return 1.0
	if randf_range(0, 100) >= float(stats.get("critical_luck")):
		return 1.0
	return maxf(1.0, float(stats.get("critical_damage")))
