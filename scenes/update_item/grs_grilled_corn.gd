extends Node2D

@onready var cd_timer = $CDTimer

var num: int
var equip_luck: int = 10
var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.enemy_fire_hurt.connect(fire_damage_heal_hp)

func first_activation():
	equip_luck = 30
	PlayerData.update_player_ability()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "grs_grilled_corn":
		return
	if current_upgrade["grs_grilled_corn"]["quantity"] == 1:
		return
	num = current_upgrade["grs_grilled_corn"]["quantity"]
	equip_luck += 15
	PlayerData.update_player_ability()

func fire_damage_heal_hp(_enemy_body: Node):
	var luck = randf_range(0,200)
	if luck < equip_luck + player.stats.luck and cd_timer.time_left <= 0:
		player.health_hp = 1
		player.emit_signal("is_health")
		cd_timer.start()
