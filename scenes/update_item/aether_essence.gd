extends EquipItem

var damage_mult: float = 1.05

func _on_equip():
	damage_mult = 1.05
	GameEvents.enemy_damage_taken.connect(update_damage)

func update_damage(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if damage_data.damage_type.has(GameTags.BULLET_DAMAGE):
		var damage: int = damage_data.base_damage
		damage_data.base_damage = ceil(damage * damage_mult)
