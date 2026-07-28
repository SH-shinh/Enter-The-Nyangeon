extends Node2D

var num: int
var player: Node

var cd_time: int = 0
var delay_time: int = 0

var t_hp_count: int = 0

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.enemy_poison_hurt.connect(add_t_hp)
	GameEvents.global_time_count.connect(time_count)

func first_activation():
	pass
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "motivation_boost_candy":
		return
	if current_upgrade["motivation_boost_candy"]["quantity"] == 1:
		return
	num = current_upgrade["motivation_boost_candy"]["quantity"]

func time_count():
	if cd_time > 0:
		cd_time -= 1
	if delay_time > 0:
		delay_time -= 1
		if delay_time <= 0:
			player.stats.t_hp += t_hp_count
			t_hp_count = 0

func add_t_hp(enemy_body: Node):
	if cd_time <= 0:
		t_hp_count += ceil(enemy_body.stats.hurt_hp * 0.03)
		cd_time = 1
	if delay_time <= 0:
		delay_time = 6
