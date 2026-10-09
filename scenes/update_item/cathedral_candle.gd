extends EquipItem

var player: Node
var health_num: int = 3
var enemy_body:Array = []
var health_cd: int = 0

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	health_num = 3
	GameEvents.global_time_count.connect(time_count)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	health_num += 3

func time_count():
	if health_cd > 0:
		health_cd -= 1

func dead_health():
	if health_cd <= 0:
		HealData.fill(player.health_component.heal_data, {
			"amount": health_num,
			"source": GameTags.EQUIP,
			"node": self,
		})
		player.health_component.take_damage(player.health_component.heal_data)
		health_cd = 1

func _on_area_2d_body_entered(body):
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Enemy"):
		enemy_body.append(body)
		if !body.stats.hp_hurt.is_connected(dead_health):
			body.stats.hp_hurt.connect(dead_health)

func _on_area_2d_body_exited(body):
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Enemy")  and enemy_body.has(body):
		enemy_body.remove_at(enemy_body.find(body))
		if body.stats.hp_hurt.is_connected(dead_health):
			body.stats.hp_hurt.disconnect(dead_health)
