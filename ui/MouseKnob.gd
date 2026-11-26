extends TouchScreenButton

## 移动端右摇杆：
## - 普通状态：按住 = 瞄准 + 持续开火（手动管理 fire action，场景里已移除
##   TouchScreenButton.action="fire"，否则触摸一按下就会开火）；
## - 玩家处于隐身（Kotama 被动）时：按住只瞄准、不开火；松手时补一发破隐射击，
##   避免刚碰右摇杆瞄准就开枪破隐；
## - 按住期间隐身自然结束/被移除：恢复“按住持续开火”。
## 开火必须用 InputEventAction 走正常输入分发（player.gd 是事件驱动）。

const DRAG_RADIS := 25.0
## 破隐单发需要让枪械 _physics_process 至少看到一次 is_shoot=true；
## physics_frame 在最前发射，因此需要跨过两个物理帧再复位。
const BREAK_SHOT_PHYSICS_FRAMES := 2

var finger_index := -1
var drag_offset: Vector2
var player: Node

var _fire_held: bool = false
var _defer_fire: bool = false
var _pulse_token: int = 0

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
	set_process(false)

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
	_defer_fire = false
	_pulse_token += 1
	set_process(false)
	_release_fire()

func _release_fire():
	if _fire_held:
		_fire_held = false
		_set_fire_action(false)

func _press_fire():
	if _fire_held:
		return
	_fire_held = true
	_set_fire_action(true)

## 必须用 InputEventAction 走正常输入分发（player.gd 是事件驱动）；
## Input.action_press() 只改动作状态、不会触发 _unhandled_input。
func _set_fire_action(pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = "fire"
	event.pressed = pressed
	Input.parse_input_event(event)

func _on_visibility_changed():
	if not is_visible_in_tree():
		_release_all()
	else:
		_refresh_rest_pos()

func _notification(what):
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_PAUSED:
		_release_all()

func _process(_delta):
	if not _defer_fire:
		set_process(false)
		return
	# 隐身自然结束/被移除：恢复“按住持续开火”
	if _is_player_stealthed():
		return
	_defer_fire = false
	set_process(false)
	_press_fire()

func _input(event: InputEvent):
	if not is_visible_in_tree():
		# 触屏 UI 被隐藏（切换鼠标/手柄、暂停等）时不能留下卡住的 fire action。
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
				_begin_fire_hold()
		elif not st.pressed and st.index == finger_index:
			_end_fire_hold()
			finger_index = -1

	var sd := event as InputEventScreenDrag
	if sd and sd.index == finger_index:
		var wish_pos := sd.position * get_canvas_transform() - drag_offset
		var movement := (wish_pos - rest_pos).limit_length(DRAG_RADIS)
		global_position = rest_pos + movement

		if movement != Vector2.ZERO:
			GameEvents.emit_crosshair_target(movement)

func _begin_fire_hold() -> void:
	_pulse_token += 1
	if _is_player_stealthed():
		_defer_fire = true
		set_process(true)
		return
	_defer_fire = false
	_press_fire()

func _end_fire_hold() -> void:
	var deferred := _defer_fire
	_defer_fire = false
	set_process(false)
	_release_fire()
	if deferred and _is_player_stealthed():
		_fire_break_shot_once()

func _is_player_stealthed() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if not player.has_method("is_stealthed"):
		return false
	return player.is_stealthed()

## 破隐单发：直接驱动枪械的 is_shoot 一个物理帧，避免与 AutoButton 共用的 fire action 状态互相干扰。
func _fire_break_shot_once() -> void:
	if player == null or not is_instance_valid(player):
		return
	var gun = player.get("gun")
	if gun == null or not is_instance_valid(gun):
		return
	if bool(gun.get("is_shoot")):
		return
	_pulse_token += 1
	var token := _pulse_token
	gun.set("is_shoot", true)
	for _i in BREAK_SHOT_PHYSICS_FRAMES:
		await get_tree().physics_frame
		if token != _pulse_token or not is_instance_valid(gun):
			if is_instance_valid(gun):
				gun.set("is_shoot", false)
			return
	gun.set("is_shoot", false)
