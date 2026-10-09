class_name DamageData
extends HealthChangeData

# 调色板：所有显示颜色的来源，改色只改这里
const COLOR_WHITE   := Color(1, 1, 1)
const COLOR_YELLOW  := Color(0.937, 0.969, 0)
const COLOR_MAGENTA := Color(0.817, 0.046, 0.631)
const COLOR_FIRE    := Color(1, 0.367, 0.178)
const COLOR_POISON  := Color(0.063, 0.54, 0.342)
const COLOR_CHILL   := Color(0.323, 0.68, 0.942)

# 各伤害类型的基础显示颜色
const TYPE_COLORS := {
	GameTags.BULLET_DAMAGE: COLOR_WHITE,
	GameTags.MELEE_DAMAGE: COLOR_WHITE,
	GameTags.EQUIP_DAMAGE: COLOR_WHITE,
	GameTags.EXPLOSION_DAMAGE: COLOR_MAGENTA,
	GameTags.CRIT_DAMAGE: COLOR_YELLOW,
	GameTags.FIRE_DAMAGE: COLOR_FIRE,
	GameTags.POISON_DAMAGE: COLOR_POISON,
	GameTags.CHILL_DAMAGE: COLOR_CHILL,
	}

# 暴击颜色：由基础色统一换算（色相向暖偏移 + 满饱和 + 提亮）；
# 白色/灰色（低饱和）没有色相，固定为黄。
# 偏移量由爆炸色 (0.817,0.046,0.631) → (0.929,0,0.341) 校准。
const CRIT_WHITE_COLOR := COLOR_YELLOW
const CRIT_HUE_SHIFT := 0.06528
const CRIT_VALUE_BOOST := 0.112
const CRIT_SATURATION := 1.0
const WHITE_MIX_WEIGHT := 0.2

@export var is_crit: bool                       #是否暴击
@export var knockback_force: int                #击退力
@export var knockback_direction: Vector2        #击退方向
@export var hit_box_center: Vector2             #HitBox中心
@export var damage_type: Array[String]          #伤害标签

func reset_data():
	base_damage = 0
	is_heal = false
	is_crit = false
	knockback_force = 0
	knockback_direction = Vector2.ZERO
	hit_box_center = Vector2.ZERO
	damage_type.clear()
	source_node = ""
	source_type.clear()
	flags.clear()
	convert_power = 0
	damage_modifier.clear()
	on_damage_dealt.clear()
	owner_peer = 0

# ---------------- 构建器 API ----------------

## 从零构建（cfg 键见 _apply_cfg）
static func make(cfg: Dictionary = {}) -> DamageData:
	return fill(null, cfg)

## 复用槽位：slot 为 null 则新建，否则全量 reset 后按 cfg 覆盖；返回该实例
static func fill(slot: DamageData, cfg: Dictionary = {}) -> DamageData:
	var d: DamageData = slot if slot != null else DamageData.new()
	d.reset_data()
	d._apply_cfg(cfg)
	return d

## 预设：标准子弹（BULLET_DAMAGE + 阵营来源标签）
static func bullet(value: int, source_faction: int, node: Node = null) -> DamageData:
	return fill(null, {
		"damage": value,
		"type": GameTags.BULLET_DAMAGE,
		"source": DamageRouter.source_tag(source_faction),
		"node": node,
	})

## 预设：近战（MELEE_DAMAGE + 阵营来源标签）
static func melee(value: int, source_faction: int, node: Node = null) -> DamageData:
	return fill(null, {
		"damage": value,
		"type": GameTags.MELEE_DAMAGE,
		"source": DamageRouter.source_tag(source_faction),
		"node": node,
	})

## 预设：爆炸
static func explosion(value: int, source_tag: String, node: Node = null) -> DamageData:
	return fill(null, {
		"damage": value,
		"type": GameTags.EXPLOSION_DAMAGE,
		"source": source_tag,
		"node": node,
	})

## 预设：装备伤害（EQUIP_DAMAGE + EQUIP 来源）
static func equip_hit(value: int, node: Node = null) -> DamageData:
	return fill(null, {
		"damage": value,
		"type": GameTags.EQUIP_DAMAGE,
		"source": GameTags.EQUIP,
		"node": node,
	})

## 预设：DOT（元素标签 + DOT_DAMAGE）
static func dot(value: int, element_tag: String, source_tag: String) -> DamageData:
	return fill(null, {
		"damage": value,
		"type": [element_tag, GameTags.DOT_DAMAGE],
		"source": source_tag,
	})

## 预设：真实伤害
static func true_hit(value: int, source_tag: String, node: Node = null) -> DamageData:
	return fill(null, {
		"damage": value,
		"type": GameTags.EQUIP_DAMAGE,
		"source": source_tag,
		"flags": [GameTags.TRUE_DAMAGE],
		"node": node,
	})

func _apply_cfg(cfg: Dictionary) -> void:
	if cfg.is_empty():
		return
	if cfg.has("damage"):
		base_damage = cfg["damage"]
	if cfg.has("crit"):
		is_crit = cfg["crit"]
	if cfg.has("convert"):
		convert_power = cfg["convert"]
	if cfg.has("knockback"):
		knockback_force = cfg["knockback"]
	if cfg.has("direction"):
		knockback_direction = cfg["direction"]
	if cfg.has("center"):
		hit_box_center = cfg["center"]
	if cfg.has("type"):
		HealthChangeData.append_to(damage_type, cfg["type"])
	if cfg.has("source"):
		HealthChangeData.append_to(source_type, cfg["source"])
	if cfg.has("flags"):
		HealthChangeData.append_to(flags, cfg["flags"])
	if cfg.has("modifiers"):
		HealthChangeData.append_to(damage_modifier, cfg["modifiers"])
	if cfg.has("on_hit"):
		HealthChangeData.append_to(on_damage_dealt, cfg["on_hit"])
	if cfg.has("node") and cfg["node"] != null:
		var n: Node = cfg["node"]
		if n.is_inside_tree():
			source_node = n.get_path()
		if not cfg.has("center") and n is Node2D:
			hit_box_center = n.global_position
	if cfg.has("owner_peer"):
		owner_peer = int(cfg["owner_peer"])
	if cfg.has("source_node"):
		source_node = NodePath(str(cfg["source_node"]))

# ---------------- 链式 setter（均返回 self） ----------------

func damage(value: int) -> DamageData:
	base_damage = value
	return self

func crit(value: bool) -> DamageData:
	is_crit = value
	return self

func type(tag: String) -> DamageData:
	if not damage_type.has(tag):
		damage_type.append(tag)
	return self

func source(tag: String) -> DamageData:
	if not source_type.has(tag):
		source_type.append(tag)
	return self

func flag(tag: String) -> DamageData:
	if not flags.has(tag):
		flags.append(tag)
	return self

func knockback(value: int) -> DamageData:
	knockback_force = value
	return self

func knockback_dir(value: Vector2) -> DamageData:
	knockback_direction = value
	return self

func center(value: Vector2) -> DamageData:
	hit_box_center = value
	return self

func convert(value: int) -> DamageData:
	convert_power = value
	return self

func from(node: Node) -> DamageData:
	if node != null:
		if node.is_inside_tree():
			source_node = node.get_path()
		if node is Node2D:
			hit_box_center = node.global_position
	return self

func add_modifier(cb: Callable) -> DamageData:
	damage_modifier.append(cb)
	return self

func add_on_hit(cb: Callable) -> DamageData:
	on_damage_dealt.append(cb)
	return self

## 结构校验：debug 下对缺失的必填项 push_warning，返回是否通过
func check() -> bool:
	if not OS.is_debug_build():
		return true
	var ok := true
	if base_damage <= 0:
		push_warning("DamageData: base_damage <= 0 (source_node=%s)" % source_node)
		ok = false
	if damage_type.is_empty():
		push_warning("DamageData: damage_type 为空 (source_node=%s)" % source_node)
		ok = false
	if source_type.is_empty():
		push_warning("DamageData: source_type 为空 (source_node=%s)" % source_node)
		ok = false
	return ok

func get_display_color() -> Color:
	if damage_type.is_empty():
		return Color.WHITE
	var base := _mix_color(TYPE_COLORS, Color.WHITE, true)
	if is_crit:
		return _to_crit_color(base)
	return base

# 按权重混合多个伤害类型的颜色；白色可降权以避免冲淡属性色
func _mix_color(colors: Dictionary, fallback: Color, discount_white: bool) -> Color:
	var mixed := Color(0, 0, 0, 0)
	var total_weight := 0.0
	for type in damage_type:
		var color: Color = colors.get(type, fallback)
		var weight := 1.0
		if discount_white and color == Color.WHITE:
			weight = WHITE_MIX_WEIGHT
		mixed += color * weight
		total_weight += weight
	if total_weight <= 0.0:
		return fallback
	mixed /= total_weight
	mixed.a = 1.0
	return mixed

# 基础色 → 暴击色：色相向暖偏移 + 满饱和 + 提亮；低饱和（白/灰）固定为 CRIT_WHITE_COLOR
func _to_crit_color(base: Color) -> Color:
	if base.s < 0.01:
		return CRIT_WHITE_COLOR
	var h := fposmod(base.h + CRIT_HUE_SHIFT, 1.0)
	var v := clampf(base.v + CRIT_VALUE_BOOST, 0.0, 1.0)
	var color := Color.from_hsv(h, CRIT_SATURATION, v)
	color.a = 1.0
	return color
