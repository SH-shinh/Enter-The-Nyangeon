class_name HealData
extends HealthChangeData

const TYPE_COLORS = {
	GameTags.HEAL_DAMAGE: Color(0.69, 0.929, 0.278),
	}

@export var is_crit: bool                       #是否暴击
@export var ignore_heal_mult: bool = false      #跳过 stats.heal_mult 乘算（固定数值治疗）

func reset_data():
	base_damage = 0
	is_heal = true
	is_crit = false
	ignore_heal_mult = false
	source_node = ""
	source_type.clear()
	flags.clear()
	convert_power = 0
	damage_modifier.clear()
	on_damage_dealt.clear()

# ---------------- 构建器 API ----------------

## 从零构建（cfg 键：amount / crit / source / flags / node / ignore_heal_mult）
static func make(cfg: Dictionary = {}) -> HealData:
	return fill(null, cfg)

## 复用槽位：slot 为 null 则新建，否则全量 reset 后按 cfg 覆盖；返回该实例
static func fill(slot: HealData, cfg: Dictionary = {}) -> HealData:
	var d: HealData = slot if slot != null else HealData.new()
	d.reset_data()
	if cfg.has("amount"):
		d.base_damage = cfg["amount"]
	if cfg.has("crit"):
		d.is_crit = cfg["crit"]
	if cfg.has("ignore_heal_mult"):
		d.ignore_heal_mult = cfg["ignore_heal_mult"]
	if cfg.has("source"):
		HealthChangeData.append_to(d.source_type, cfg["source"])
	if cfg.has("flags"):
		HealthChangeData.append_to(d.flags, cfg["flags"])
	if cfg.has("node") and cfg["node"] != null:
		var n: Node = cfg["node"]
		if n.is_inside_tree():
			d.source_node = n.get_path()
	return d

## 预设：治疗
static func heal(amount: int, source_tag: String, node: Node = null) -> HealData:
	return fill(null, {"amount": amount, "source": source_tag, "node": node})

func get_display_color() -> Color:
	var mixed = Color(0,0,0,0)
	if is_crit:
		mixed = Color(0.29, 0.729, 0.378)
	else:
		mixed = TYPE_COLORS.get(GameTags.HEAL_DAMAGE, Color.WHITE)
	mixed.a = 1.0
	return mixed
