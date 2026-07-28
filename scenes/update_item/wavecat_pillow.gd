extends Node2D

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

var num: int
var player: Node
var value: Array

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	player = get_tree().get_first_node_in_group("Player")
	value = [buff_layer, buff_value, buff_erase_timer]
	GameEvents.enemy_critical_hurt.connect(add_melee_buff)

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "wavecat_pillow":
		return
	if current_upgrade["wavecat_pillow"]["quantity"] == 1:
		return
	num = current_upgrade["wavecat_pillow"]["quantity"]
	

func add_melee_buff(_enemy_body: Node):
	player.player_buff_manager.apply_buff(player_buff, value)
