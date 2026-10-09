extends SupportCharacter

var pick_manager: Node

func _special_effect() -> void:
	# 联机：医疗箱生成由 host 按各端支援聚合统一处理，本端不重复触发
	if ExtensionHooks.is_lan_session.is_valid() and bool(ExtensionHooks.is_lan_session.call()):
		return
	GameEvents.player_taken_medkit.connect(add_medical_kit)

# 联机：供 host 聚合各端支援对医疗箱生成的影响（每次拾取额外生成 1 个）
func get_medkit_spawn_modifiers() -> Dictionary:
	return {"on_take_spawn": 1}

func add_medical_kit(_taken_position: Vector2):
	if pick_manager == null:
		pick_manager = get_tree().get_first_node_in_group("PickManager")
	if pick_manager != null:
		pick_manager.add_medical_kit(Vector2.ZERO)
