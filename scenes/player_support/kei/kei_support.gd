extends SupportCharacter

# kei 支援：特殊效果为生成召唤物 kei 进场；被动数值由 SupportCharacter 统一处理。

@export var summoned_pack: PackedScene

func _special_effect() -> void:
	if summoned_pack == null:
		return
	var ins = summoned_pack.instantiate()
	ins.global_position = global_position
	get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)
