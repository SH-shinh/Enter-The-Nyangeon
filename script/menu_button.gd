extends PanelContainer

@export var button_id: String

var on_touch: bool = false

@onready var animation_player = $AnimationPlayer

func _ready():
	mouse_entered.connect(mouse_entered_anim)
	mouse_exited.connect(mouse_exitedd_anim)
	gui_input.connect(menu_button_press)
	GameEvents.player_card_touch.connect(touch_out)

func mouse_entered_anim():
	SoundManager.play_sfx("ButtonSounds2")
	animation_player.play("on_select")

func mouse_exitedd_anim():
	animation_player.play_backwards("on_select")

func touch_out():
	await get_tree().create_timer(0.05).timeout
	
	if on_touch == true:
		on_touch = false
		animation_player.play_backwards("on_select")

func menu_button_press(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if on_touch == false:
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			on_touch = true
			mouse_entered_anim()
		else:
			GameEvents.emit_check_data()
			SoundManager.play_sfx("ButtonSounds")
			SoundManager.play_sfx("UISounds1")
			GameEvents.emit_menu_button(button_id)
	
	if event.is_action_pressed("shoot"):
		GameEvents.emit_check_data()
		SoundManager.play_sfx("ButtonSounds")
		SoundManager.play_sfx("UISounds1")
		GameEvents.emit_menu_button(button_id)
