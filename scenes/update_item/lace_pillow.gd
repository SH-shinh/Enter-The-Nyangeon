extends EquipItem

# 蕾丝枕头：子弹命中满血敌人时提高本次伤害；1/2/3 件 → 200%/300%/400%。
# 只写目标 health_component.damage_multiplier（前置数值阶段），由 health_component._resolve_damage
# 在本次命中末尾消费并复位；真伤不经过该乘区（与 peroro_wheel 同口径）。

## 按件数的最终伤害倍率。
const DAMAGE_MULT: Array[float] = [2.0, 3.0, 4.0]

var _damage_mult: float = DAMAGE_MULT[0]

func _setup() -> void:
	GameEvents.enemy_damage_calculating.connect(_on_enemy_damage_calculating)

func _apply_effect(quantity: int) -> void:
	_damage_mult = DAMAGE_MULT[clampi(quantity, 1, DAMAGE_MULT.size()) - 1]

func _on_enemy_damage_calculating(_final_damage: int, damage_data: DamageData, body_path: NodePath) -> void:
	if damage_data == null or not damage_data.damage_type.has(GameTags.BULLET_DAMAGE):
		return
	var body: Node = get_node_or_null(body_path)
	if body == null:
		return
	var stats = body.get("stats")
	var health = body.get("health_component")
	if stats == null or health == null:
		return
	var max_hp: int = int(stats.get("max_hp"))
	if max_hp <= 0 or int(stats.get("hp")) < max_hp:
		return
	health.damage_multiplier += (_damage_mult - 1.0)
