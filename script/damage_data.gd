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
	is_crit = false
	knockback_force = 0
	knockback_direction = Vector2.ZERO
	damage_type.clear()
	source_node = ""
	source_type.clear()
	flags.clear()
	convert_power = 0
	damage_modifier.clear()
	on_damage_dealt.clear()

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
