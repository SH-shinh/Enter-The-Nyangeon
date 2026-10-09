extends Node2D

var joy_box: Array[Node]
var joy_index: int = -1
var can_joy: bool = true

var on_menu: bool = false
var menu_index: int = 1

@onready var h_box_container = $Node2D/HBoxContainer

func _ready():
	GameEvents.menu_changed.connect(get_menu_changed)

func _unhandled_input(event):
	if on_menu:
		joy_select(event)

func get_menu_changed(changed_index):
	if changed_index == menu_index:
		await get_tree().process_frame
		on_menu = true

func joy_select(event: InputEvent):
	if event.is_action_pressed("ui_down"):
		SoundManager.play_sfx("ButtonSounds2")
		on_menu = false
		var now_menu_index = wrapi(menu_index + 1, 0, 2)
		GameEvents.emit_menu_changed(now_menu_index)
	elif event.is_action_pressed("ui_up"):
		SoundManager.play_sfx("ButtonSounds2")
		on_menu = false
		var now_menu_index = wrapi(menu_index - 1, 0, 2)
		GameEvents.emit_menu_changed(now_menu_index)
	
	if can_joy:
		can_joy = false
		if !h_box_container.get_children().is_empty():
			joy_box.clear()
			joy_box = h_box_container.get_children()
		
		if !joy_box.is_empty():
			if joy_box[0] == null:
				joy_box.clear()
				joy_index = 0
		
		if event.is_action_pressed("ui_left"):
			joy_index = wrapi(joy_index - 1, 0, joy_box.size())
			joy_button()
		
		elif event.is_action_pressed("ui_right"):
			joy_index = wrapi(joy_index + 1, 0, joy_box.size())
			joy_button()
		
		elif event.is_action_pressed("ui_accept"):
			joy_button()
		await get_tree().process_frame
		can_joy = true

func joy_button():
	joy_box[joy_index].touch_button()
