extends Node2D

@export var player_buff: Buff
@onready var millennium_flag_icon = preload("res://scenes/update_item/millennium_flag_icon.tscn")

var value: Array = []
var group: Array = []
var num: int

@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

var player: Node
var equip_luck: int = 5

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.enemy_hit_position.connect(add_buff)

func first_activation():
	
	value = [buff_layer, buff_value, buff_erase_timer]
	equip_luck = 5
	PlayerData.bullet_speed_mult += 0.1
	PlayerData.update_player_ability()
	var sprite_2d = millennium_flag_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "millennium_flag":
		return
	if current_upgrade["millennium_flag"]["quantity"] == 1:
		return
	num = current_upgrade["millennium_flag"]["quantity"]
	value = [buff_layer, buff_value, buff_erase_timer]
	equip_luck += 5
	PlayerData.update_player_ability()

func add_buff(_hit_body: Node):
	if randf_range(0,300) < player.stats.luck + equip_luck:
		player.player_buff_manager.apply_buff(player_buff, value)
