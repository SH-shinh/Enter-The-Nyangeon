extends ScrollContainer

var isDrag: bool = false
var start_pos: float = 0

func _ready():
	gui_input.connect(set_scrollbox_gui_input)

func set_scrollbox_gui_input(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		isDrag = true
		start_pos = event.position.x
	
	if event as InputEventScreenTouch and !event.pressed:
		isDrag = false
		start_pos = 0
	
	if event.is_pressed() and event is InputEventMouseButton:
		isDrag = true
		start_pos = event.position.x
	
	if !event.is_pressed() and event is InputEventMouseButton:
		isDrag = false
		start_pos = 0
	
	if isDrag == true:
		var offset = event.position.x - start_pos
		self.scroll_horizontal -= offset
		start_pos = event.position.x
