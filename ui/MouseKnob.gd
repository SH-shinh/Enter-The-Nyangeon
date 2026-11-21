extends TouchScreenButton

const DRAG_RADIS := 25.0


var finger_index := -1
var drag_offset: Vector2
var player: Node

var rest_pos: Vector2
var _rest_local: Vector2

func _ready():
	_rest_local = position
	rest_pos = global_position
	GameEvents.get_player.connect(get_player)
	GameEvents.round_start.connect(reset_position)
	Game.game_mode_changed.connect(_release_all)
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(_refresh_rest_pos)
	call_deferred("_refresh_rest_pos")

# 旋转/分屏后父 Control 的锚点位置会变，归位点必须按父节点当前变换重算。
func _refresh_rest_pos():
	var parent_item := get_parent() as CanvasItem
	if parent_item != null:
		rest_pos = parent_item.get_global_transform() * _rest_local
	else:
		rest_pos = global_position

func get_player():
	player = get_tree().get_first_node_in_group("Player")

func reset_position():
	_release_all()
	global_position = rest_pos

func _release_all():
	finger_index = -1

func _on_visibility_changed():
	if not is_visible_in_tree():
		_release_all()
	else:
		_refresh_rest_pos()

func _notification(what):
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_PAUSED:
		_release_all()

func _input(event: InputEvent):
	
	var st := event as InputEventScreenTouch
	
	if st:
		if st.canceled:
			if st.index == finger_index:
				_release_all()
			return
		
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
		
	
