extends EquipItem

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

var value: Array

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	value = [buff_layer, buff_value, buff_erase_timer]
	GameEvents.enemy_damage_taken.connect(add_melee_buff)

func add_melee_buff(_final_damage: int, damage_data: DamageData, _body_path: NodePath):
	if damage_data.is_crit == true:
		player.player_buff_manager.apply_buff(player_buff, value)
