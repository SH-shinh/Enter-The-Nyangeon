extends EquipItem

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var cowboy_hat_icon = preload("res://scenes/update_item/cowboy_hat_icon.tscn")

var group: Array =[]
var value: Array

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	value = [buff_layer, buff_value, buff_erase_timer]

func _setup():
	GameEvents.player_gun_shoot.connect(add_buff)

func add_buff(_gun: Node):
	player.player_buff_manager.apply_buff(player_buff, value)
