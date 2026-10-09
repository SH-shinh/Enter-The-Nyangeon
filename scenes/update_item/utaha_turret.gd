extends EquipItem

@onready var turret = preload("res://scenes/update_item/utaha_turret_body.tscn")

var spawn_point: Vector2 = Vector2(704, 448)

func _on_equip():
	add_turret()

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	add_turret()

func add_turret():
	var turret_position = spawn_point + Vector2( randf_range(-80,80), randf_range(-50,50)  )
	var ins = turret.instantiate()
	ins.global_position = turret_position
	get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)
