extends EquipItem

@onready var turret = preload("res://scenes/update_item/utaha_turret_body.tscn")

func _on_equip():
	add_turret()

func _apply_effect(quantity: int):
	if quantity == 1:
		return
	add_turret()

func add_turret():
	var ins = turret.instantiate()
	# 落点跟着玩家走（而不是写死地图中心），壁垒回合也不会埋在墙里。
	ins.global_position = TurretSummoned.spawn_point_for(self)
	get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)
