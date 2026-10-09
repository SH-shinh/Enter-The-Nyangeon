extends EquipItem

@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@onready var fuel_tank_icon: PackedScene = preload("res://scenes/update_item/fuel_tank_icon.tscn")
var group: Array
var value: Array
var add_layer: int = 1

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	value = [buff_layer, buff_value, buff_erase_timer]
	add_layer = 1
	group = get_tree().get_nodes_in_group("Muzzle")
	for i in group:
		if i.muzzle_use == false:
			var sprite_2d = fuel_tank_icon.instantiate()
			i.add_child(sprite_2d)
			i.muzzle_use = true

func _setup():
	GameEvents.enemy_damage_taken.connect(add_buff)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	#buff_layer += 2
	#buff_value *= 1
	#buff_erase_timer *= 1
	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.fire_dot_layer_add +=2
	add_layer += 1

func add_buff(_final_damage: int, damage_data: DamageData, body_path: NodePath):
	if damage_data.damage_type.has(GameTags.BULLET_DAMAGE):
		var enemy_body: Node = get_node_or_null(body_path)
		if enemy_body == null:
			return
		for i in add_layer:
			enemy_body.enemy_buff_manager.apply_buff(enemy_buff, value)
