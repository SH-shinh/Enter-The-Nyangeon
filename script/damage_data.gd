class_name DamageData
extends HealthChangeData

# 调色板：所有显示颜色的来源，改色只改这里
const COLOR_WHITE   := Color(1, 1, 1)
const COLOR_YELLOW  := Color(0.937, 0.969, 0)
const COLOR_MAGENTA := Color(0.817, 0.046, 0.631)
const COLOR_CRIMSON := Color(0.929, 0, 0.341)
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

# 暴击时各伤害类型的显示颜色（未列出的类型走 DEFAULT_CRIT_COLOR）
const TYPE_CRIT_COLORS := {
	GameTags.EXPLOSION_DAMAGE: COLOR_CRIMSON,
	}

const DEFAULT_CRIT_COLOR := COLOR_YELLOW
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
	if is_crit:
		return _get_crit_color()
	return _mix_color(TYPE_COLORS, Color.WHITE, true)

# 暴击颜色：只取有专门暴击色的类型，一个都没有时回退到默认暴击色
func _get_crit_color() -> Color:
	var mixed := Color(0, 0, 0, 0)
	var count := 0
	for type in damage_type:
		if TYPE_CRIT_COLORS.has(type):
			mixed += TYPE_CRIT_COLORS[type]
			count += 1
	if count == 0:
		return DEFAULT_CRIT_COLOR
	mixed /= count
	mixed.a = 1.0
	return mixed

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
