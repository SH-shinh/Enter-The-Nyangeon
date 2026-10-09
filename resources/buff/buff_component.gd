class_name BuffComponent
extends Node

var manager: Node
var body: Node

func setup(p_manager: Node, p_body: Node) -> void:
	manager = p_manager
	body = p_body

func activate(_entry: Dictionary) -> void:
	pass

func refresh(_entry: Dictionary) -> void:
	pass

func deactivate() -> void:
	pass
