extends Node2D

@export var enemy_buff: Buff
@onready var red_ninpero_icon = preload("res://scenes/update_item/red_ninpero_icon.tscn")

var value: Array = []
var group: Array = []
var num: int

@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

var player: Node

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.enemy_fire_hurt.connect(add_buff)

func first_activation():
	
	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.bullet_speed_mult *= 1.05
	PlayerData.update_player_ability()
	var sprite_2d = red_ninpero_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "red_ninpero":
		return
	if current_upgrade["red_ninpero"]["quantity"] == 1:
		return
	num = current_upgrade["red_ninpero"]["quantity"]
	buff_layer += 5
	buff_value *= 1
	buff_erase_timer *= 1
	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.update_player_ability()

func add_buff(enemy_body: Node):
	enemy_body.enemy_buff_manager.apply_buff(enemy_buff, value)
