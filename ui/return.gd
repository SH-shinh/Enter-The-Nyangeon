extends Button

func _on_pressed() -> void:
	Game.pause_press()

func _on_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		accept_event()
		_on_pressed()
	elif event as InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		_on_pressed()
	elif event.is_action_pressed("ui_accept"):
		accept_event()
		_on_pressed()
