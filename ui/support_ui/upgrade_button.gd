extends PanelContainer

@onready var lv_button_anim: AnimationPlayer = $lv_button_anim
@onready var close_timer: Timer = $CloseTimer
@onready var h_slider: HSlider = $Node2D2/HSlider
@onready var now_cost: Label = %NowCost

var on_select: bool = false
var on_scroll: bool = false

var isDrag: bool = false
var start_pos: float = 0

func _ready() -> void:
	mouse_entered.connect(mouse_in)
	mouse_exited.connect(mouse_out)
	gui_input.connect(press_button)
	h_slider.mouse_entered.connect(mouse_in_scroll)
	h_slider.mouse_exited.connect(mouse_out_scroll)
	h_slider.value_changed.connect(move_cost_label)
	h_slider.gui_input.connect(set_scrollbox_gui_input)
	close_timer.timeout.connect(close_menu)
	PlayerData.pyroxenes_changed.connect(get_player_pyroxenes)
	move_cost_label(0)

func get_player_pyroxenes():
	h_slider.max_value = PlayerData.player_pyroxenes
	h_slider.value = 0
	now_cost.text = str(0)

func add_support_upgrade():
	var n = h_slider.value
	if PlayerData.player_pyroxenes >= n and SupportData.now_lv > 0:
		if SupportData.now_exp < (SupportData.max_exp + 200):
			PlayerData.player_pyroxenes -= n
			SupportData.now_exp += 200 * n
			SupportData.save_data()
			SupportData.check_upgrade()
			get_player_pyroxenes()
			SoundManager.play_sfx("CoinCostSounds")
		else:
			SoundManager.play_sfx("ButtonSounds")
		
	else:
		SoundManager.play_sfx("ButtonSounds")

func move_cost_label(value: float):
	var n = value / h_slider.max_value
	now_cost.position.x = 4 + 61 * n
	now_cost.text = str(value)

func mouse_in_scroll():
	on_scroll = true
	SoundManager.play_sfx("ButtonSounds2")
	if close_timer.time_left > 0:
		close_timer.stop()
	
func mouse_out_scroll():
	on_scroll = false

func mouse_in():
	if !lv_button_anim.is_playing():
		SoundManager.play_sfx("ButtonSounds2")
		lv_button_anim.play("mouse_in")
	if close_timer.time_left > 0:
		close_timer.stop()

func mouse_out():
	if !lv_button_anim.is_playing():
		lv_button_anim.play_backwards("mouse_in")
		
	if on_select:
		close_timer.start()

func open_menu():
	on_select = true
	get_player_pyroxenes()
	lv_button_anim.play("selected")

func close_menu():
	lv_button_anim.play_backwards("selected")
	await lv_button_anim.animation_finished
	lv_button_anim.play_backwards("mouse_in")
	on_select = false

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
