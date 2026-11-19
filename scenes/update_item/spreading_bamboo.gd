extends EquipItem

## 蔓延竹笋：提高支援 EX 范围（range_mult）。
## 当前 range_mult 作用于 KEI 光环半径与 AYANE 单发爆炸半径；SERINA 无范围，道具门控已排除。

const MULT_BY_STACK := [1.3, 1.4, 1.5]

var _stack: int = 1

func _apply_effect(quantity: int) -> void:
	_stack = clampi(quantity, 1, MULT_BY_STACK.size())
	if is_instance_valid(SupportData):
		SupportData.set_ex_modifiers(item_id, {"range_mult": float(MULT_BY_STACK[_stack - 1])})

func _exit_tree() -> void:
	if is_instance_valid(SupportData):
		SupportData.clear_ex_modifiers(item_id)
	super()
