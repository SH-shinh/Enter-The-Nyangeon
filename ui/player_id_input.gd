extends Control

@export var can_input: bool = true

@onready var player_id: LineEdit = $player_id
@onready var submit: Button = $submit_button
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func input_screen_show():
	if can_input:
		animation_player.play("enter_anim")
		player_id.focus_mode = Control.FOCUS_ALL
		await get_tree().process_frame
		player_id.grab_focus()

func input_screen_hide():
	self.visible = false
	player_id.focus_mode = Control.FOCUS_NONE

func _on_color_rect_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		player_id.release_focus()
	
	if event.is_action_pressed("shoot"):
		player_id.release_focus()

func _on_player_id_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		player_id.grab_focus()
		SoundManager.play_sfx("ButtonSounds2")
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds2")
	
	if event.is_action_pressed("ui_accept"):
		player_id.release_focus()

func _on_submit_button_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	# 1. 获取玩家输入的内容（去除首尾空格）
	var player_id_local = player_id.text.strip_edges()
	
	# 2. 基础验证：不能为空
	if player_id_local == "":
		if !animation_player.is_playing():
			animation_player.play("warning_anim")
	else:
		GameEvents.emit_player_id_print(player_id_local)
		input_screen_hide()

func _on_cancel_button_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	input_screen_hide()


func _is_button_press(event: InputEvent) -> bool:
	if event as InputEventScreenTouch and event.pressed:
		return true
	if event as InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		return true
	if event.is_action_pressed("ui_accept"):
		return true
	return false

func _on_submit_button_gui_input(event: InputEvent) -> void:
	if _is_button_press(event):
		_on_submit_button_pressed()

func _on_cancel_button_gui_input(event: InputEvent) -> void:
	if _is_button_press(event):
		_on_cancel_button_pressed()
