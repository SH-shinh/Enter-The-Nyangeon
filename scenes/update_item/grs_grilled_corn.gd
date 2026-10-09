extends EquipItem

const HEAL_CD: float = 0.03

var equip_luck: int = 10
var _cd: float = 0.0

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	equip_luck = 30
	set_physics_process(false)

func _setup():
	GameEvents.enemy_damage_taken.connect(fire_damage_heal_hp)

func _physics_process(delta: float) -> void:
	_cd -= delta
	if _cd <= 0.0:
		_cd = 0.0
		set_physics_process(false)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	equip_luck += 15

func fire_damage_heal_hp(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if damage_data.damage_type.has(GameTags.FIRE_DAMAGE):
		var luck = randf_range(0,200)
		if luck < equip_luck + player.stats.luck and _cd <= 0.0:
			HealData.fill(player.health_component.heal_data, {
				"amount": 1,
				"source": GameTags.EQUIP,
				"node": self,
			})
			player.health_component.take_damage(player.health_component.heal_data)
			_cd = HEAL_CD
			set_physics_process(true)
