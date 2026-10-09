extends EquipItem

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@onready var thermal_scope_icon: PackedScene = preload("res://scenes/update_item/thermal_scope_icon.tscn")

var group: Array
var value: Array
var player: Node

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	value = [buff_layer, buff_value, buff_erase_timer]
	attach_rail_icon(thermal_scope_icon)

func _setup():
	GameEvents.player_shot_not_critical.connect(add_buff)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.critical_damage_add += 0.15

func add_buff(_bullet_body: Node):
	player.player_buff_manager.apply_buff(player_buff, value)
