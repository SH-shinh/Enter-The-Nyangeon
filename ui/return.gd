extends Button

func _on_pressed() -> void:
	Game.pause_press()

func _on_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch:
		_on_pressed()
