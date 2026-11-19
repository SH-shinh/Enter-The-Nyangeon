extends EquipItem

## 幸运彩蛋：玩家侧暴击命中时回复 EX 充能（按需求百分比），内置 0.5s 冷却。
## 伤害类型白名单避免 DOT/共享 DamageData 的 is_crit 残留误触发。

const PERCENT_BY_STACK := [0.05, 0.10, 0.15]
const COOLDOWN_MS := 500
const CHARGE_DAMAGE_TYPES := ["bullet_damage", "melee_damage", "explosion_damage", "equip_damage"]

var _stack: int = 1
var _last_charge_ms: int = -COOLDOWN_MS

func _apply_effect(quantity: int) -> void:
	_stack = clampi(quantity, 1, PERCENT_BY_STACK.size())

func _setup() -> void:
	GameEvents.enemy_damage_taken.connect(_on_enemy_damage_taken)

func _on_enemy_damage_taken(_final_damage: int, damage_data: DamageData, _body_path: NodePath) -> void:
	if damage_data == null or not damage_data.is_crit:
		return
	if SupportData.ex_cost <= 0 or not _is_charge_damage(damage_data):
		return
	var now := Time.get_ticks_msec()
	if now - _last_charge_ms < COOLDOWN_MS:
		return
	_last_charge_ms = now
	var pct: float = PERCENT_BY_STACK[_stack - 1]
	SupportData.add_ex_charge(float(SupportData.ex_cost) * pct)

func _is_charge_damage(damage_data: DamageData) -> bool:
	for damage_type in CHARGE_DAMAGE_TYPES:
		if damage_data.damage_type.has(damage_type):
			return true
	return false
