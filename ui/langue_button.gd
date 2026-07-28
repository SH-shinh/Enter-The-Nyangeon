extends Node2D

@onready var option_button: OptionButton = $OptionButton
@onready var touch_menu: Node2D = $touch_menu

var on_touch: bool = false

func _ready() -> void:
	_set_button(Game.game_language)
	option_button.gui_input.connect(touch_input)
	GameEvents.player_card_touch.connect(close_touch_menu)

func touch_input(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		open_touch_menu()

func open_touch_menu():
	on_touch = true
	touch_menu.visible = true

func close_touch_menu():
	if on_touch == true:
		on_touch = false
		touch_menu.visible = false

func _set_button(langue: String):
	match langue:
		"zh_CN":
			option_button.selected = 0
		"en":
			option_button.selected = 1
		"pt":
			option_button.selected = 2

func _on_option_button_item_selected(index: int) -> void:
	var n: int
	match index:
		0:
			Game.game_language = "zh_CN"
			TranslationServer.set_locale("zh_CN")
			Game.save_config()
		1:
			Game.game_language = "en"
			TranslationServer.set_locale("en")
			Game.save_config()
		2:
			Game.game_language = "pt"
			TranslationServer.set_locale("pt")
			Game.save_config()


func _on_option_button_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")


func _on_zh_cn_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		option_button.selected = 0
		_on_option_button_item_selected(0)
		close_touch_menu()


func _on_en_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		option_button.selected = 1
		_on_option_button_item_selected(1)
		close_touch_menu()


func _on_pt_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		option_button.selected = 2
		_on_option_button_item_selected(2)
		close_touch_menu()
