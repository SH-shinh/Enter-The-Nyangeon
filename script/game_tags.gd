class_name GameTags

#伤害来源标签
const PLAYER: String = "player"
const PS_DAMAGE: String = "ps_damage"
const EQUIP: String = "equip"
const SUMMONED: String = "summoned"
const CONVERTED: String = "converted"  #策反单位
const NEUTRAL: String = "neutral"      #不分敌我

const MAP: String = "map"              #来自场景

const ENEMY: String = "enemy"

#伤害类型
const CRIT_DAMAGE: String = "crit_damage"

const BULLET_DAMAGE: String = "bullet_damage"

const MELEE_DAMAGE: String = "melee_damage"

const EXPLOSION_DAMAGE: String = "explosion_damage"

const FIRE_DAMAGE: String = "fire_damage"
const POISON_DAMAGE: String = "poison_damage"
const CHILL_DAMAGE: String = "chill_damage"

const EQUIP_DAMAGE: String = "equip_damage"

const DOT_DAMAGE: String = "dot_damage"   #来源于dot伤害

const HEAL_DAMAGE: String = "heal_damage"  #治疗

#特殊flags
const KNOCKBACK_ATTRACT: String = "knockback_attract" #击退方向为反向
const TRUE_DAMAGE: String = "true_damage" #真实伤害
const WEAK_DAMAGE: String = "weak_damage"  #弱点伤害
const CONVERT: String = "convert"  #策反积蓄
const EXTRA_DAMAGE: String = "extra_damage" #额外伤害请求（发起方防递归用）
const SPLIT_CHILD: String = "split_child" #分裂产物子弹：不再触发分裂
