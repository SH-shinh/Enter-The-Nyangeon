extends EquipItem

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
		_play_range_fx()


# 范围提示（纯视觉）：环重新滚一次 + 在原地冒大号/小号 "+"。
# 联机镜像的根脚本被 set_script(null)，不会走到这里；环与常态小号仍会自播。
func _play_range_fx() -> void:
	var ring := get_node_or_null("Node2D/HealRing")
	if not is_instance_valid(ring):
		return
	if ring.has_method("play"):
		ring.call("play")
	var spawner := ring.get_node_or_null("PlusSpawner")
	if is_instance_valid(spawner) and spawner.has_method("burst"):
		spawner.call("burst")


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
