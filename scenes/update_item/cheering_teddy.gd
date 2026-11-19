extends EquipItem

## 应援玩偶：提高支援 EX 技能倍率（power_mult）。
## 作用点：KEI 光环 buff 值、SERINA 治疗 buff/每秒治疗、AYANE 基础爆炸伤害。

const MULT_BY_STACK := [1.3, 1.4, 1.5]

var _stack: int = 1

func _apply_effect(quantity: int) -> void:
	_stack = clampi(quantity, 1, MULT_BY_STACK.size())
	if is_instance_valid(SupportData):
		SupportData.set_ex_modifiers(item_id, {"power_mult": float(MULT_BY_STACK[_stack - 1])})

func _exit_tree() -> void:
	if is_instance_valid(SupportData):
		SupportData.clear_ex_modifiers(item_id)
	super()
