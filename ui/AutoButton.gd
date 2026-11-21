extends PanelContainer

@onready var press = $Press
@onready var release = $Release
@onready var timer = $Timer

var on_press: bool = false

func _ready():
	gui_input.connect(auto_press)
	visibility_changed.connect(_on_visibility_changed)

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		auto_close()

func _on_visibility_changed():
	if not is_visible_in_tree():
		auto_close()

func fire_input(press: bool):
	var event = InputEventAction.new()
	event.action = "fire"
	event.pressed = press
	Input.parse_input_event(event)

func auto_fire():
	on_press = true
	press.visible = true
	release.visible = false
	timer.start()
	fire_input(true)

func auto_close():
	# 隐藏/失焦/暂停时必须停表并补发 fire=false，否则切设备隐藏摇杆后仍持续开火。
	on_press = false
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
