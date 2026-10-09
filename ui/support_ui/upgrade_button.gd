extends PanelContainer

const RETRACT_DELAY: float = 2.0
const NOW_COST_WIDTH: float = 40.0

@onready var lv_button_anim: AnimationPlayer = $lv_button_anim
@onready var close_timer: Timer = $CloseTimer
@onready var h_slider: HSlider = $Node2D2/HSlider
@onready var now_cost: Label = %NowCost
@onready var node_2d_2: Node2D = $Node2D2

var on_select: bool = false
var _closing: bool = false

var isDrag: bool = false
var start_pos: float = 0

var click_catcher: Control

func _ready() -> void:
	mouse_entered.connect(mouse_in)
	mouse_exited.connect(mouse_out)
	gui_input.connect(press_button)
	h_slider.mouse_entered.connect(mouse_in)
	h_slider.mouse_exited.connect(mouse_out)
	h_slider.value_changed.connect(move_cost_label)
	h_slider.gui_input.connect(set_scrollbox_gui_input)
	close_timer.wait_time = RETRACT_DELAY
	close_timer.one_shot = true
	close_timer.timeout.connect(close_menu)
	PlayerData.pyroxenes_changed.connect(get_player_pyroxenes)
	_create_click_catcher()
	node_2d_2.visible = false
	now_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	move_cost_label(0)

func _create_click_catcher() -> void:
	click_catcher = Control.new()
	click_catcher.name = "ClickCatcher"
	click_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	click_catcher.visible = false
	click_catcher.gui_input.connect(_on_click_catcher_gui_input)
	var parent := get_parent() as Node2D
	parent.add_child.call_deferred(click_catcher)
	parent.move_child.call_deferred(click_catcher, 0)
	_fit_click_catcher.call_deferred()

func _fit_click_catcher() -> void:
	if click_catcher == null:
		return
	var parent: Node2D = get_parent() as Node2D
	var inv: Transform2D = parent.get_global_transform_with_canvas().affine_inverse()
	var top_left: Vector2 = inv * Vector2.ZERO
	var bottom_right: Vector2 = inv * get_viewport_rect().size
	click_catcher.position = top_left
	click_catcher.size = bottom_right - top_left

func _on_click_catcher_gui_input(event: InputEvent) -> void:
	if on_select == false:
		return
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pressed = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	if pressed:
		click_catcher.accept_event()
		close_menu()

func get_player_pyroxenes():
	h_slider.max_value = min(PlayerData.player_pyroxenes, SupportData.get_upgrade_max_stones())
	h_slider.value = 0
	now_cost.text = str(0)

func add_support_upgrade():
	var n = min(int(h_slider.value), SupportData.get_upgrade_max_stones())
	if n > 0 and PlayerData.player_pyroxenes >= n and SupportData.now_lv > 0:
		PlayerData.player_pyroxenes -= n
		SupportData.now_exp += SupportData.EXP_PER_PYROXENE * n
		SupportData.save_data()
		SupportData.check_upgrade()
		get_player_pyroxenes()
		SoundManager.play_sfx("CoinCostSounds")
	else:
		SoundManager.play_sfx("ButtonSounds")

func move_cost_label(value: float):
	var max_value = h_slider.max_value
	var n = 0.0 if max_value <= 0.0 else value / max_value
	now_cost.text = str(int(value))
	now_cost.size.x = NOW_COST_WIDTH
	now_cost.position.x = (14 + 61 * n) - NOW_COST_WIDTH

func mouse_in():
	if on_select == false:
		SoundManager.play_sfx("ButtonSounds2")
		open_menu()
	else:
		close_timer.stop()

func mouse_out():
	if on_select and not get_global_rect().has_point(get_global_mouse_position()):
		close_timer.start()

func open_menu():
	if on_select:
		return
	on_select = true
	get_player_pyroxenes()
	lv_button_anim.play("selected")
	if click_catcher != null:
		_fit_click_catcher()
		click_catcher.visible = true

func close_menu():
	if on_select == false or _closing:
		return
	_closing = true
	if click_catcher != null:
		click_catcher.visible = false
	close_timer.stop()
	lv_button_anim.play_backwards("selected")
	await lv_button_anim.animation_finished
	node_2d_2.visible = false
	on_select = false
	_closing = false

func set_scrollbox_gui_input(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		isDrag = true
		start_pos = event.position.x
	
	if event as InputEventScreenTouch and !event.pressed:
		isDrag = false
		start_pos = 0
	
	if isDrag == true:
		var offset = (event.position.x - start_pos) * 0.5
		h_slider.value += offset
		start_pos = event.position.x

func press_button(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if on_select == false:
			SoundManager.play_sfx("ButtonSounds")
			open_menu()
		else:
			add_support_upgrade()
	
	if event.is_action_pressed("shoot"):
		if on_select == false:
			SoundManager.play_sfx("ButtonSounds")
			open_menu()
		else:
			add_support_upgrade()
