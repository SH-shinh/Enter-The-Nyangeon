extends PanelContainer

@export var button_id: String
@onready var animation_player = $AnimationPlayer

var on_show: bool = false

func _ready():
	mouse_entered.connect(mouse_entered_anim)
	mouse_exited.connect(mouse_exitedd_anim)
	gui_input.connect(menu_button_press)

func mouse_entered_anim():
	if on_show == false:
		SoundManager.play_sfx("ButtonSounds2")
		animation_player.play("on_select")

func mouse_exitedd_anim():
	if on_show == false:
		animation_player.play_backwards("on_select")

func menu_button_press(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		GameEvents.emit_menu_button(button_id)
		animation_player.play("selected")
		on_show = true
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		GameEvents.emit_menu_button(button_id)
		animation_player.play("selected")
		on_show = true
