extends EquipItem

## 回礼手帕：EX 结束后返还按需求百分比的充能。
## SupportAS.skill_end 先把 now_cost 归零，再发 support_ex_end，因此这里从 0 起算。

const PERCENT_BY_STACK := [0.3, 0.4, 0.5]

var _stack: int = 1

func _apply_effect(quantity: int) -> void:
	_stack = clampi(quantity, 1, PERCENT_BY_STACK.size())

func _setup() -> void:
	GameEvents.support_ex_end.connect(_on_support_ex_end)

func _on_support_ex_end() -> void:
	if SupportData.ex_cost <= 0:
		return
	var pct: float = PERCENT_BY_STACK[_stack - 1]
	SupportData.add_ex_charge(float(SupportData.ex_cost) * pct)
