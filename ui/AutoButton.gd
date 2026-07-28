extends PanelContainer

@onready var press = $Press
@onready var release = $Release
@onready var timer = $Timer

var on_press: bool = false

func _ready():
	gui_input.connect(auto_press)

func fire_input(press: bool):
	var event = InputEventAction.new()
	event.action = "fire"
	event.pressed = press
	Input.parse_input_event(event)

func auto_fire():
	press.visible = true
	release.visible = false
	timer.start()
	fire_input(true)

func auto_close():
	press.visible = false
	release.visible = true
	timer.stop()
	fire_input(false)

func auto_press(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if on_press == false:
			on_press = true
			auto_fire()
		else:
			on_press = false
			auto_close()

func _on_timer_timeout():
	fire_input(true)
