extends EquipItem

var health_num: float = 0.01
@onready var health_cd_timer = $HealthCDTimer
@onready var cd_delay_timer = $CDDelayTimer

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	PlayerData.max_hp_add += 10
	health_num = 0.01

func _setup():
	GameEvents.enemy_damage_taken_dead.connect(dead_health)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.max_hp_add += 10
	health_num += 0.01

func dead_health(final_damage: int, _damage_data: DamageData, _body_path: NodePath):
	if health_cd_timer.time_left <= 0:
		var health_hp = ceil(final_damage * health_num)
		HealData.fill(player.health_component.heal_data, {
			"amount": health_hp,
			"source": GameTags.MAP,
			"node": self,
		})
		player.health_component.take_damage(player.health_component.heal_data)
		if cd_delay_timer.is_stopped():
			cd_delay_timer.start()

func _on_cd_delay_timer_timeout():
	health_cd_timer.start()
