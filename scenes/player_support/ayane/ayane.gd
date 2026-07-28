extends Node2D

var pick_manager: Node

func _ready() -> void:
	GameEvents.player_taken_medkit.connect(add_medical_kit)

func add_medical_kit(_taken_position: Vector2):
	if pick_manager == null:
		pick_manager = get_tree().get_first_node_in_group("PickManager")
	if pick_manager != null:
		pick_manager.add_medical_kit(Vector2.ZERO)
