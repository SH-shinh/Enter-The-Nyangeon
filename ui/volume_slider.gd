extends HSlider

@export var bus: StringName = "Master"

@onready var bus_index := AudioServer.get_bus_index(bus)

var isDrag: bool = false
var start_pos: float = 0

func _ready():
	
	gui_input.connect(set_scrollbox_gui_input)
	
	value = SoundManager.get_volume(bus_index)
	
	value_changed.connect(func (v: float):
		SoundManager.set_volume(bus_index, v)
		Game.save_config()
		)

func set_scrollbox_gui_input(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		isDrag = true
		start_pos = event.position.x
	
	if event as InputEventScreenTouch and !event.pressed:
		isDrag = false
		start_pos = 0
	
	if isDrag == true:
		var offset = (event.position.x - start_pos) * 0.01
		self.value += offset
		start_pos = event.position.x
