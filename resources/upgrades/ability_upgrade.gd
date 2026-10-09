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
@export_flags("弹道", "爆炸", "装备", "概率", "暴击", "燃烧", "中毒", "恶寒", "防御", "生命", "成长", "召唤", "近战", "速度", "护甲", "金币", "策反") var item_tags: int = 0
@export var tags: Array[String]
@export var weight: float = 1.0  # 基础权重

func has_tag(tag: ItemType) -> bool:
	return (item_tags & tag) != 0

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
	}
	for tag in tag_dict:
		if has_tag(tag):
			names.append(tag_dict[tag])
	return names
