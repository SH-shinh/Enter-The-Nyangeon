extends PanelContainer

signal button_select
signal button_close

@export var tag_name: String

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var label: Label = $Node2D/Label

var is_open: bool = false

func _ready() -> void:
	label.text = tag_name
	gui_input.connect(select_button)

func select_button(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		open_shop_menu()
	
	if event.is_action_pressed("shoot"):
		open_shop_menu()

func open_shop_menu():
	if is_open == false:
		is_open = true
		mouse_filter = 2
		SoundManager.play_sfx("ButtonSounds")
		animation_player.play("select_anim")
		button_select.emit()

func close_shop_menu():
	if is_open == true:
		is_open = false
		animation_player.play_backwards("select_anim")
		await animation_player.animation_finished
		mouse_filter = 0
