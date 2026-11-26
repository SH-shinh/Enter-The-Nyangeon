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
	# 只有本按钮确实在开火时才补发 fire=false；隐藏/失焦时不能清掉鼠标/键盘正在按的 fire。
	var was_pressing: bool = on_press
	on_press = false
	press.visible = false
	release.visible = true
	timer.stop()
	if was_pressing:
		fire_input(false)

func auto_press(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if on_press == false:
			on_press = true
			auto_fire()
		else:
			auto_close()

func _on_timer_timeout():
	fire_input(true)
