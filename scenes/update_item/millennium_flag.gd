extends EquipItem

@export var player_buff: Buff
@onready var millennium_flag_icon = preload("res://scenes/update_item/millennium_flag_icon.tscn")

var value: Array = []
var group: Array = []

@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

var player: Node
var equip_luck: int = 5

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")

	value = [buff_layer, buff_value, buff_erase_timer]
	equip_luck = 5
	PlayerData.bullet_speed_mult += 0.1
	var sprite_2d = millennium_flag_icon.instantiate()
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
	value = [buff_layer, buff_value, buff_erase_timer]
	equip_luck += 5

func add_buff(_final_damage: int, _damage_data: DamageData, _body_path: NodePath):
	if randf_range(0,300) < player.stats.luck + equip_luck:
		player.player_buff_manager.apply_buff(player_buff, value)
