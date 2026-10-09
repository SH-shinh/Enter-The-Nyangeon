class_name DamageRouter

# 策反单位伤害基数 = 玩家子弹伤害，吃召唤物加成 + 全局伤害加成
static func converted_damage(player: Node, source: Node = null) -> int:
	if player == null or player.get("stats") == null:
		return 0
	var damage_add: float = 0
	var damage_mult: float = 1
	if source != null and source.get("stats") != null:
		var source_add = source.stats.get("ally_damage_add")
		if source_add != null:
			damage_add = source_add
		var source_mult = source.stats.get("ally_damage_mult")
		if source_mult != null:
			damage_mult = source_mult
	return max(1, int((player.stats.bullet_damage + damage_add) * player.stats.summoned_damage * player.stats.global_damage * damage_mult))

# 根据施法者阵营决定伤害来源标签
static func source_tag(faction: int) -> String:
	return GameTags.CONVERTED if faction == Faction.PLAYER_SIDE else GameTags.ENEMY

# 击退/策反抗性统一按百分比结算：100 = 完全免疫，返回 0.0
static func resist_factor(resist_pct: int) -> float:
	return 1.0 - clampf(resist_pct * 0.01, 0.0, 1.0)

# 击退量化基准：1 单位 = 100 力值
const KB_UNIT := 100

# 玩家/召唤物击退抗性的边际递减：软上限起点以下线性，超出部分指数饱和至渐近上限
const KNOCKBACK_RESIS_SOFT := 70.0
const KNOCKBACK_RESIS_CAP := 90.0
const KNOCKBACK_RESIS_SCALE := 50.0

static func diminish_resist(raw: float) -> float:
	if raw <= KNOCKBACK_RESIS_SOFT:
		return raw
	return KNOCKBACK_RESIS_SOFT + (KNOCKBACK_RESIS_CAP - KNOCKBACK_RESIS_SOFT) \
		* (1.0 - exp(-(raw - KNOCKBACK_RESIS_SOFT) / KNOCKBACK_RESIS_SCALE))

# 统一抗性入口（玩家/敌人共用）：>=100 硬免疫，否则套边际递减，返回 0-100
static func apply_knockback_resist(raw: float) -> int:
	if raw >= 100.0:
		return 100
	return clampi(int(round(diminish_resist(raw))), 0, 100)

# 对原始抗性套统一递减（含 >=100 硬免疫）后，再换算成击退保留系数
static func diminishing_factor(raw: float) -> float:
	return 1.0 - clampf(apply_knockback_resist(raw) * 0.01, 0.0, 1.0)

# 抗性结算后，近战类伤害额外击退倍率
const MELEE_KNOCKBACK_MULT := 1.5

static func melee_knockback_mult(damage_type: Array) -> float:
	if damage_type.has(GameTags.MELEE_DAMAGE):
		return MELEE_KNOCKBACK_MULT
	return 1.0

# 根据阵营计算最终基础伤害（策反走玩家加成，否则保持原值）
static func scaled_damage(source_faction: int, base_damage: float, node: Node) -> float:
	if source_faction == Faction.PLAYER_SIDE:
		return converted_damage(node.get_tree().get_first_node_in_group("Player"), node)
	return base_damage
