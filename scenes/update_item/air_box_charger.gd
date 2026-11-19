extends EquipItem

## 支援充电盒：每秒按 EX 需求百分比自动充能（不区分是否在 EX 中，充满后 clamp）。

const PERCENT_BY_STACK := [0.05, 0.10, 0.15]

var _stack: int = 1
var _timer: Timer

func _apply_effect(quantity: int) -> void:
	_stack = clampi(quantity, 1, PERCENT_BY_STACK.size())

func _setup() -> void:
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	_timer.start()

func _on_tick() -> void:
	if SupportData.ex_cost <= 0:
		return
	var pct: float = PERCENT_BY_STACK[_stack - 1]
	SupportData.add_ex_charge(float(SupportData.ex_cost) * pct)

func _exit_tree() -> void:
	if _timer != null:
		_timer.stop()
	super()
