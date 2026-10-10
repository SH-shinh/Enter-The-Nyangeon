class_name KeiAura
extends BuffAura

## kei EX 光环：对玩家/远端镜像用玩家数值，对召唤物用召唤物数值。
## 远端召唤物由 mod 扫描转发，统一使用召唤物数值（network_aura_value）。

@export var buff_layer_2: int = 1
@export var buff_value_2: float = 0.25
@export var buff_erase_timer_2: float = 999.0


func aura_value_for(body: Node) -> Array:
	if body != null and body.is_in_group("Summoned"):
		return [buff_layer_2, buff_value_2, buff_erase_timer_2]
	return [buff_layer, buff_value, buff_erase_timer]


func network_aura_value() -> Array:
	return [buff_layer_2, buff_value_2, buff_erase_timer_2]
