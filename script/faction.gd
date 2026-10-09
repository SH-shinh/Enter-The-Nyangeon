class_name Faction

const PLAYER_SIDE := 0
const ENEMY_SIDE := 1
const NEUTRAL := 2
const ANY := -1

# 根据伤害来源标签推断所属阵营（非 ENEMY 一律视为玩家侧，含 CONVERTED/SUMMONED/EQUIP/MAP/DOT）
static func of_source(source_type: Array) -> int:
	if source_type.has(GameTags.NEUTRAL):
		return NEUTRAL
	if source_type.has(GameTags.ENEMY):
		return ENEMY_SIDE
	return PLAYER_SIDE

# 判断某伤害来源是否与目标阵营敌对（false = 友军免伤）
static func hostile_to(source_type: Array, target_team: int) -> bool:
	return of_source(source_type) != target_team

# 推断任意节点的阵营（敌人有 faction 字段；玩家/召唤物/策反单位靠 group 兜底）
static func of_entity(node: Node) -> int:
	if node == null:
		return ENEMY_SIDE
	if node.get("faction") != null:
		return node.faction
	if node.is_in_group("Summoned") or node.is_in_group("Converted") or node.is_in_group("Player"):
		return PLAYER_SIDE
	return ENEMY_SIDE
