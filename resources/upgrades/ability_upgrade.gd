extends Resource
class_name AbilityUpgrade

# 稀有度配色（0/1/2），供升级选卡与测试房道具卡共用
const RARITY_COLORS := [
	Color(0.159, 0.27, 0.419),
	Color(0.567, 0.399, 0.116),
	Color(0.96, 0.38, 0.535),
]

enum ItemType {
	NONE = 0,
	TRAJECTORY = 1 << 0,
	EXPLOSION = 1 << 1,
	EQUIP = 1 << 2,
	PROBABILITY = 1 << 3,
	CRITICAL = 1 << 4,
	FIRE = 1 << 5,
	POISON = 1 << 6,
	COLD = 1 << 7,
	DEFENSE = 1 << 8,
	HEALTH = 1 << 9,
	GROWTH = 1 << 10,
	SUMMON = 1 << 11,
	MELEE = 1 << 12,
	SPEED = 1 << 13,
	ARMOR = 1 << 14,
	COIN = 1 << 15,
	CONVERT = 1 << 16,
	SHOCK = 1 << 17,
}

@export var id: String
@export var icon: Texture2D
@export var name: String
@export_range(0,2) var rare: int
@export_range(-1 , 99) var order_num: int = -1
@export var special_rules: int = 0
@export_multiline var description: String
@export_multiline var forward: String
@export_multiline var negative: String
@export_flags("弹道", "爆炸", "装备", "概率", "暴击", "燃烧", "中毒", "恶寒", "防御", "生命", "成长", "召唤", "近战", "速度", "护甲", "金币", "策反", "感电") var item_tags: int = 0
@export var tags: Array[String]
@export var weight: float = 1.0  # 基础权重
## 是否走「防御门控」（首发不可抽 → 随回合累积 → 抽中清零 → 拥有数封顶）。
## 默认按 DEFENSE 标签统一门控；混搭道具若要豁免，在对应 .tres 里置 false。
@export var defense_weight_gated: bool = true

## 入池门控（支援 EX 类道具）：与防御门控不同，这是「资格」而不是权重乘区——
## UpgradeManager 在算权重前直接过滤，不满足时道具根本不会进入候选/池。
enum SupportGate {
	NONE = 0,      # 不限制（默认，旧资源/旧 Mod 行为不变）
	ANY = 1,       # 本局有出战支援（任意角色）才入池
	SPECIFIC = 2,  # 本局出战支援在 support_ids 中才入池
}
@export_enum("不限制", "任意支援", "指定支援") var support_gate: int = SupportGate.NONE
## SPECIFIC 时生效；空列表视为永不入池（UpgradeManager 启动时告警）。
@export var support_ids: Array[String] = []

func has_tag(tag: ItemType) -> bool:
	return (item_tags & tag) != 0

## 本局出战支援 id 是否满足入池条件；"null"/"" 表示没有可用支援（fail-closed）。
func support_gate_ok(support_id: String) -> bool:
	var active := support_id != "" and support_id != "null"
	match support_gate:
		SupportGate.ANY:
			return active
		SupportGate.SPECIFIC:
			return active and support_ids.has(support_id)
		_:
			return true

func get_tag_list() -> Array:
	var tag_list = []
	for tag in ItemType.values():
		if has_tag(tag):
			tag_list.append(tag)
	return tag_list

func get_tag_names() -> Array:
	var names = []
	var tag_dict = {
		ItemType.TRAJECTORY: "弹道",
		ItemType.EXPLOSION: "爆炸",
		ItemType.EQUIP: "装备",
		ItemType.PROBABILITY: "概率",
		ItemType.CRITICAL: "暴击",
		ItemType.FIRE: "燃烧",
		ItemType.POISON: "中毒",
		ItemType.COLD: "恶寒",
		ItemType.DEFENSE: "防御",
		ItemType.HEALTH: "生命",
		ItemType.GROWTH: "成长",
		ItemType.SUMMON: "召唤",
		ItemType.MELEE: "近战",
		ItemType.SPEED: "速度",
		ItemType.ARMOR: "护甲",
		ItemType.COIN: "金币",
		ItemType.SHOCK: "感电",
	}
	for tag in tag_dict:
		if has_tag(tag):
			names.append(tag_dict[tag])
	return names
