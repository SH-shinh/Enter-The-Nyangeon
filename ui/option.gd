extends Node2D

@onready var animation_player = $AnimationPlayer
@onready var option_button_box = $Node2D/option_button_box/VBoxContainer
@onready var menu_box = $menu_box


var on_option: bool = false

func _ready():
	GameEvents.menu_button.connect(menu_button_press)
	ExtensionHooks.notify(ExtensionHooks.populate_option_pages, [menu_box, option_button_box])

func on_option_selected():
	animation_player.play("option_in")
	on_option = true

func out_option_selected():
	SoundManager.play_sfx("UISounds2")
	animation_player.play("option_out")
	on_option = false

func button_open():
	var buttons: Array = option_button_box.get_children()
	for i in buttons:
		i.mouse_filter = Control.MOUSE_FILTER_STOP

func button_close():
	var buttons: Array = option_button_box.get_children()
	for i in buttons:
		i.mouse_filter = Control.MOUSE_FILTER_IGNORE

func menu_button_press(button_id: String):

	var matched: bool = false
	var menus: Array = menu_box.get_children()

	for i in menus:
		if i.option_id == button_id:
			i.menu_show()
			matched = true

	if matched:
		botton_out_anim(button_id)

func botton_out_anim(button_id: String):

	var buttons: Array = option_button_box.get_children()

	for i in buttons:
		if i.button_id != button_id and i.on_show:
			i.on_show = false
			i.mouse_exitedd_anim()

	var menus: Array = menu_box.get_children()

	for i in menus:
		if i.option_id != button_id:
			i.menu_hide()
