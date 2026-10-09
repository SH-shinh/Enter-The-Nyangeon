extends EquipItem

var robotic_vacuum_cleaner: Node

@onready var robotic_vacuum_cleaner_body: PackedScene = preload("res://scenes/update_item/robotic_vacuum_cleaner_body.tscn")

func _on_equip():
	var body = robotic_vacuum_cleaner_body.instantiate()
	get_tree().get_first_node_in_group("PlayerRoot").add_child(body)
	robotic_vacuum_cleaner = body
	body.global_position = self.global_position

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	if robotic_vacuum_cleaner != null:
		robotic_vacuum_cleaner.equip_speed += 50
		robotic_vacuum_cleaner.equip_range += 0.3
		robotic_vacuum_cleaner.update_body()
