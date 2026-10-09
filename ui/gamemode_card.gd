extends PanelContainer

@onready var item_icon = $Node2D/TextureRect
@onready var item_text = %ItemText
@onready var text_show = $Node2D/Text
@onready var item_text_4: Label = %ItemText4

var text_is_show: bool = false
var card_id: String

var on_touch: bool = false

func _ready():
	GameEvents.player_card_touch.connect(touch_out)
	gui_input.connect(touch_show)
	mouse_entered.connect(show_text)
	mouse_exited.connect(hide_text)

func _physics_process(delta: float) -> void:
	if text_is_show == true:
		if on_touch == false:
			text_show.global_position = get_global_mouse_position()
		else:
			text_show.global_position = self.global_position

func set_gamemode_card(gamemode_card: GameMode):
	if gamemode_card != null:
		item_icon.texture = gamemode_card.game_mode_icon
		card_id = gamemode_card.game_mode_id
		item_text_4.text = card_id + "_id"
		item_text.text = card_id + "_description"

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
	text_show.visible = true
	text_is_show = true

func hide_text():
	text_show.visible = false
	text_is_show = false
