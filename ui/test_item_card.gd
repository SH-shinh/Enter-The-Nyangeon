extends PanelContainer

@onready var texture_rect = $TextureRect
@onready var item_text_2 = %ItemText2
@onready var item_text_3 = %ItemText3
@onready var item_text_4: Label = %ItemText4
@onready var item_text = %ItemText
@onready var text_show = $Text
@onready var button: Button = $Button

var upgrade_manager: Node
var up_c: AbilityUpgrade
var text_is_show: bool = false
var on_touch: bool = false
var num: int = 0

var touch_start_position = Vector2()
var touch_start_time = 0
const MAX_TAP_DISTANCE = 10
const MAX_TAP_TIME = 0.3

func _ready():
	GameEvents.player_card_touch.connect(touch_out)
	GameEvents.get_player.connect(_reset)
	GameEvents.test_room_button_close.connect(close_button)
	GameEvents.test_room_reset.connect(open_button)
	gui_input.connect(touch_show)
	mouse_entered.connect(show_text)
	mouse_exited.connect(hide_text)

func open_button():
	button.mouse_filter = 1

func close_button():
	button.mouse_filter = 2

func _physics_process(delta: float) -> void:
	if text_is_show == true:
		if on_touch == false:
			text_show.global_position = get_global_mouse_position()
		else:
			text_show.global_position = self.global_position

func _reset():
	num = up_c.order_num

func touch_out():
	await get_tree().create_timer(0.05).timeout
	
	if on_touch == true:
		on_touch = false
		text_show.visible = false

func touch_show(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		if on_touch == false:
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			on_touch = true
			text_show.visible = true
			text_is_show = true

func show_text():
	SoundManager.play_sfx("ButtonSounds2")
	text_show.visible = true
	text_is_show = true

func hide_text():
	text_show.visible = false
	text_is_show = false

func get_card(upgrade_card: AbilityUpgrade):
	up_c = upgrade_card
	texture_rect.texture = up_c.icon
	item_text_4.text = up_c.id + "_name"
	item_text.text = up_c.id + "_description"
	item_text_2.text = up_c.id + "_forward"
	item_text_3.text = up_c.id + "_negative"
	num = up_c.order_num

func add_card():
	upgrade_manager.apply_upgrade(up_c)

func _on_button_pressed():
	if num == 0:
		SoundManager.play_sfx("ButtonSounds2")
	else:
		if num > 0:
			num -= 1
		SoundManager.play_sfx("ButtonSounds")
		add_card()

func _on_button_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed and on_touch == true:
		_on_button_pressed()
