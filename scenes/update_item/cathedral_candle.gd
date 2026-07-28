extends Node2D

var num: int
var player: Node
var health_num: int = 3
var enemy_body:Array = []
var health_cd: int = 0

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	health_num = 3
	GameEvents.global_time_count.connect(time_count)
	PlayerData.update_player_ability()

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "cathedral_candle":
		return
	if current_upgrade["cathedral_candle"]["quantity"] == 1:
		return
	num = current_upgrade["cathedral_candle"]["quantity"]
	health_num += 3
	PlayerData.update_player_ability()

func time_count():
	if health_cd > 0:
		health_cd -= 1

func dead_health():
	if health_cd <= 0:
		player.health_hp = health_num
		player.emit_signal("is_health")
		health_cd = 1


func _on_area_2d_body_entered(body):
	if body.is_in_group("Enemy"):
		enemy_body.append(body)
		if !body.stats.hp_hurt.is_connected(dead_health):
			body.stats.hp_hurt.connect(dead_health)

func _on_area_2d_body_exited(body):
	if body.is_in_group("Enemy")  and enemy_body.has(body):
		enemy_body.remove_at(enemy_body.find(body))
		if body.stats.hp_hurt.is_connected(dead_health):
			body.stats.hp_hurt.disconnect(dead_health)
