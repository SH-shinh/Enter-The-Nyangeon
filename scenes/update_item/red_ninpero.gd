extends EquipItem

@export var enemy_buff: Buff
@onready var red_ninpero_icon = preload("res://scenes/update_item/red_ninpero_icon.tscn")

var value: Array = []
var group: Array = []

@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

var player: Node

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")

	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.bullet_speed_mult += 0.05
	var sprite_2d = red_ninpero_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true

func _setup():
	GameEvents.enemy_damage_taken.connect(add_buff)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	buff_layer += 5
	buff_value = 1
	buff_erase_timer = 1
	value = [buff_layer, buff_value, buff_erase_timer]

func add_buff(_final_damage: int, damage_data: DamageData, body_path: NodePath):
	if damage_data.damage_type.has(GameTags.FIRE_DAMAGE):
		var enemy_body: Node = get_node_or_null(body_path)
		if enemy_body == null:
			return
		enemy_body.enemy_buff_manager.apply_buff(enemy_buff, value)
