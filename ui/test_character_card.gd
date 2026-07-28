extends PanelContainer

@onready var sprite_2d: Sprite2D = $ColorRect/Sprite2D
@onready var button: Button = $Button
@onready var ps_text: Label = %PSText
@onready var text_show: Node2D = $Text

var player_card: PlayerCard
var player_id: String
var player_path: String
var on_touch: bool = false
var text_is_show: bool = false

func _ready() -> void:
	GameEvents.test_room_button_close.connect(close_button)
	GameEvents.test_room_reset.connect(open_button)
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

func open_button():
	button.mouse_filter = 1

func close_button():
	button.mouse_filter = 2

func load_player_card():
	if player_card != null:
		sprite_2d.texture = player_card.sprite
		player_id = player_card.id
		ps_text.text = player_card.id + "_ps_0"
		player_path = "res://scenes/player/" + player_id + "/" + player_id + ".tscn"

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

func _on_button_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	get_tree().paused = true
	GameEvents.emit_test_room_button_close()
	GameEvents.emit_teset_room_now_player(player_path)
	Transition.play_left_start()
	await Transition.left_end_start
	var player = get_tree().get_first_node_in_group("Player")
	if player != null:
		player.queue_free()
	var path = load(player_path)
	var ins = path.instantiate()
	get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)
	Transition.play_left_end()
	await Transition.animation_player.animation_finished
	GameEvents.emit_test_room_reset()
	get_tree().paused = false

func _on_button_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and !event.pressed and on_touch:
		_on_button_pressed()
