extends BuffComponent

const DEBT_VALUE: Array[float] = [0, 0.9, 0.8, 0.6, 0.4, 0.01]
const COIN_GET: Array[float] = [0, 0.2, 0.4, 0.8, 1.5, 3]

var active: bool = false
var coin: float = 0.0

func activate(entry: Dictionary) -> void:
	if active:
		return
	active = true
	var idx: int = clampi(int(entry["value"]), 0, DEBT_VALUE.size() - 1)
	PlayerData.ability_mult = DEBT_VALUE[idx]
	var raw: Array = entry.get("raw_value", [])
	var coin_gate: float = float(raw[3]) if raw.size() > 3 else 0.0
	if coin_gate > 0.0:
		coin = COIN_GET[idx]
		PlayerData.coin_mult_add += coin
	PlayerData.update_player_ability()

func deactivate() -> void:
	if not active:
		return
	active = false
	PlayerData.ability_mult = 1
	if coin != 0.0:
		PlayerData.coin_mult_add -= coin
		coin = 0.0
	PlayerData.update_player_ability()
