extends Node2D

var num: int
var player: Node
var health_num: float = 0.01
@onready var health_cd_timer = $HealthCDTimer

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.enemy_dead_hurt_damage.connect(dead_health)

func first_activation():
	PlayerData.max_hp_add += 10
	health_num = 0.01
	PlayerData.update_player_ability()

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "mandrake_seed":
		return
	if current_upgrade["mandrake_seed"]["quantity"] == 1:
		return
	num = current_upgrade["mandrake_seed"]["quantity"]
	PlayerData.max_hp_add += 10
	health_num += 0.01
	PlayerData.update_player_ability()

func dead_health(hurt_damage):
	if health_cd_timer.time_left <= 0:
		player.health_hp = ceil(hurt_damage * health_num)
		player.emit_signal("is_health")
		await get_tree().create_timer(0.1).timeout
		health_cd_timer.start()
