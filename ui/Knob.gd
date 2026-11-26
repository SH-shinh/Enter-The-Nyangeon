extends TouchScreenButton

const DRAG_RADIS := 25.0


var finger_index := -1
var drag_offset: Vector2

var rest_pos: Vector2
var _rest_local: Vector2
# 只记录摇杆自己按下的 move_* 动作：键盘/手柄也共用这些 InputMap action，
# 摇杆隐藏/模式切换时不能无条件 action_release，否则会把键盘按住的方向键一起清掉。
var _owned_actions: Dictionary = {}

func _ready():
	_rest_local = position
	rest_pos = global_position
	GameEvents.round_start.connect(reset_position)
	Game.game_mode_changed.connect(_release_all)
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(_refresh_rest_pos)
	call_deferred("_refresh_rest_pos")

# 旋转/分屏后父 Control 的锚点位置会变，归位点必须按父节点当前变换重算，不能只缓存一次。
func _refresh_rest_pos():
	var parent_item := get_parent() as CanvasItem
	if parent_item != null:
		rest_pos = parent_item.get_global_transform() * _rest_local
	else:
		rest_pos = global_position

func reset_position():
	_release_all()
	global_position = rest_pos

func _release_all():
	for action in _owned_actions.keys():
		Input.action_release(action)
	_owned_actions.clear()
	finger_index = -1

func _press_owned(action: StringName, strength: float) -> void:
	Input.action_press(action, strength)
	_owned_actions[action] = true

func _release_owned(action: StringName) -> void:
	if _owned_actions.has(action):
		_owned_actions.erase(action)
		Input.action_release(action)

func _on_visibility_changed():
	if not is_visible_in_tree():
		_release_all()
	else:
		_refresh_rest_pos()

func _notification(what):
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_PAUSED:
		_release_all()

func _input(event: InputEvent):
	if not is_visible_in_tree():
		_release_all()
		return

	var st := event as InputEventScreenTouch
	
	if st:
		if st.canceled:
			if st.index == finger_index:
				_release_all()
			return
		if st.pressed and finger_index == -1:
			var global_pos := st.position * get_canvas_transform()
			var local_pos := global_pos * get_global_transform()
			var rect := Rect2(Vector2.ZERO, texture_normal.get_size())
			if rect.has_point(local_pos):
				finger_index = st.index
				drag_offset = global_pos - global_position
		elif not st.pressed and st.index == finger_index:
			
			_release_all()
			global_position = rest_pos
	
	var sd := event as InputEventScreenDrag
	if sd and sd.index == finger_index:
		var wish_pos := sd.position * get_canvas_transform() - drag_offset
		var movement := (wish_pos - rest_pos).limit_length(DRAG_RADIS)
		global_position = rest_pos + movement
		
		movement /= DRAG_RADIS
		if movement.x > 0:
			_release_owned(&"move_left")
			_press_owned(&"move_right", movement.x)
		elif movement.x < 0:
			_release_owned(&"move_right")
			_press_owned(&"move_left", -movement.x)
		else:
			_release_owned(&"move_left")
			_release_owned(&"move_right")
		
		if movement.y > 0:
			_release_owned(&"move_up")
			_press_owned(&"move_down", movement.y)
		elif movement.y < 0:
			_release_owned(&"move_down")
			_press_owned(&"move_up", -movement.y)
		else:
			_release_owned(&"move_up")
			_release_owned(&"move_down")
