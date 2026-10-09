extends EquipItem

var chance: float = 5.0
var banana_group: Array[Node]
var index: int = 0
@onready var BANANA: PackedScene = preload("res://scenes/banana.tscn")

func _on_equip():
	PlayerData.max_ammo_add += 8

func _setup():
	GameEvents.player_gun_shoot.connect(add_banana)

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	PlayerData.max_ammo_add += 8
	chance += 2

func get_banana():
	var max_value: int = banana_group.size()
	var banana: Node = null
	if max_value > 0:
		banana = banana_group.get(index)

	if banana == null:
		banana = BANANA.instantiate()
		get_tree().get_first_node_in_group("SELayer").add_child(banana)
		banana_group.push_back(banana)

	else:
		if max_value > 20:
			banana.idle_state()

		if banana.is_idle == 1:
			index = wrapi(index + 1, 0, max_value)

		if banana.is_idle == 0:
			banana = BANANA.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(banana)
			banana_group.push_back(banana)

	return banana

func add_banana(gun: Node):
	if randf_range(0, 100) < chance:
		var banana = get_banana()
		if banana != null:
			banana.global_position = gun.shoot_position.global_position
			banana.active_state()
