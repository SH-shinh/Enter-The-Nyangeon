extends TouchScreenButton

const DRAG_RADIS := 25.0


var finger_index := -1
var drag_offset: Vector2
var player: Node

@onready var rest_pos := global_position

func _ready():
	GameEvents.get_player.connect(get_player)

func get_player():
	player = get_tree().get_first_node_in_group("Player")

func _input(event: InputEvent):
	
	var st := event as InputEventScreenTouch
	
	if st:
		
		#Input.action_press("fire")
		
		if st.pressed and finger_index == -1:
			var global_pos := st.position * get_canvas_transform()
			var local_pos := global_pos * get_global_transform()
			var rect := Rect2(Vector2.ZERO, texture_normal.get_size())
			
			
			if rect.has_point(local_pos):
				finger_index = st.index
				drag_offset = global_pos - global_position
		elif not st.pressed and st.index == finger_index:
			
			#Input.action_release("fire")
			finger_index = -1
			#global_position = rest_pos
	
	var sd := event as InputEventScreenDrag
	if sd and sd.index == finger_index:
		var wish_pos := sd.position * get_canvas_transform() - drag_offset
		var movement := (wish_pos - rest_pos).limit_length(DRAG_RADIS)
		global_position = rest_pos + movement
		
		#movement /= DRAG_RADIS
		
		if movement != Vector2.ZERO:
			#Input.action_press("fire", 1)
			GameEvents.emit_crosshair_target(movement)
		
	
