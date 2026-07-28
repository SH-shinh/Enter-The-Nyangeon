extends Node

signal summoned_changed

var summoned_group: Array = []



func _on_area_2d_body_entered(body):
	if body.is_in_group("Summoned"):
		summoned_group.append(body)
		summoned_changed.emit()


func _on_area_2d_body_exited(body):
	if body.is_in_group("Summoned"):
		summoned_group.remove_at(summoned_group.find(body))
		summoned_changed.emit()
