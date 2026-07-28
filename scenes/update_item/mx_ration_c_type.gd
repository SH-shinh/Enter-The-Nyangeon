extends Node2D

signal value_count_change

var num: int
var player: Node
@onready var value_count: int = 0:
	set(v):
		v = max(0, v)
		if value_count == v:
			return
		value_count = v
		value_count_change.emit()
var hurt_resis_value: int = 0

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.player_melee_hit_enemy.connect(hurt_resis_count)
	GameEvents.player_hurt_hp.connect(hurt_remove)
	GameEvents.player_hurt_t_hp.connect(hurt_remove)
	GameEvents.round_end.connect(reset_value)
	value_count_change.connect(player_update)
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "mx_ration_c_type":
		return
	if current_upgrade["mx_ration_c_type"]["quantity"] == 1:
		return
	num = current_upgrade["mx_ration_c_type"]["quantity"]

func hurt_resis_count(_body: Node):
	value_count += 1

func player_update():
	PlayerData.hurt_resis_add -= hurt_resis_value
	hurt_resis_value = value_count
	PlayerData.hurt_resis_add += hurt_resis_value
	PlayerData.update_player_ability()

func reset_value():
	value_count = 0

func hurt_remove(hurt_hp: int):
	value_count -= value_count * 0.5
