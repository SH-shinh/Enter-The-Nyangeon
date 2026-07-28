extends Node

signal transition_middle

const transition_1 = preload("res://ui/transition.tscn")

func _ready():
	GameEvents.transition_start.connect(transition_start)
	transition_middle.connect(transition_end)

func emit_transition_middle():
	transition_middle.emit()

func transition_start():
	var transition_ins = transition_1.instantiate()
	get_tree().get_root().add_child(transition_ins)
	transition_ins.left_end_start.connect(emit_transition_middle)
	transition_ins.play_left_start()

func transition_end():
	var transition_ins = transition_1.instantiate()
	get_tree().get_root().add_child(transition_ins)
	transition_ins.play_left_end()
