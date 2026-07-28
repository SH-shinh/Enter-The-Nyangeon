extends PanelContainer

@export var gamemode_card: GameMode
@export var gamemode_conflicting: Array[String]

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var label: Label = $VBoxContainer/Label
@onready var texture_rect: TextureRect = $VBoxContainer/TextureRect
@onready var text_show: Node2D = $Text
@onready var item_text: Label = %ItemText

var game_mode: String
var on_selected: bool = false
var on_touch: bool = false
var show_text: bool = false

func _ready() -> void:
	mouse_entered.connect(_mouse_enter)
	mouse_exited.connect(_mouse_exit)
	gui_input.connect(gamemode_selected)
	GameEvents.gamemode_conflicting.connect(has_game_mode_conflicting)

func _process(delta: float) -> void:
	if label.size.x > 39:
		var now_font = label.get("theme_override_font_sizes/font_size")
		if now_font > 1:
			now_font -= 1
			label.set("theme_override_font_sizes/font_size", now_font)

func _physics_process(delta: float) -> void:
	if show_text == true:
		if on_touch == false:
			text_show.global_position = get_global_mouse_position()
		else:
			text_show.global_position = self.global_position

func get_gamemode_card():
	gamemode_conflicting = gamemode_card.gamemode_conflicting
	label.text = str(gamemode_card.game_mode_name) + "_id"
	game_mode = gamemode_card.game_mode_id
	texture_rect.texture = gamemode_card.game_mode_icon
	item_text.text = str(gamemode_card.game_mode_name) + "_description"
	if PlayerData.game_mode.has(game_mode):
		on_selected = true
		animation_player.play("full_anim")

func open_mouse():
	mouse_filter = 0

func close_mouse():
	mouse_filter = 2

func _mouse_enter() -> void:
	show_text = true
	text_show.visible = true
	if on_selected == false:
		SoundManager.play_sfx("ButtonSounds2")
		animation_player.play("select_anim")
	else:
		SoundManager.play_sfx("ButtonSounds2")
		animation_player.play("full_select")

func _mouse_exit():
	show_text = false
	text_show.visible = false
	if on_selected == false:
		animation_player.play_backwards("select_anim")
	else:
		animation_player.play_backwards("full_select")

func touch_out():
	await get_tree().create_timer(0.05).timeout
	
	if on_selected == false and on_touch == true:
		on_touch = false
		animation_player.play_backwards("select_anim")

func add_game_mode():
	close_mouse()
	on_selected = true
	SoundManager.play_sfx("ButtonSounds")
	if !PlayerData.game_mode.has(game_mode):
		PlayerData.game_mode.append(game_mode)
		GameEvents.emit_gamemode_conflicting(gamemode_conflicting)
		Game.save_playerdata()
	animation_player.play("full_anim")
	await animation_player.animation_finished
	open_mouse()

func erase_game_mode():
	close_mouse()
	on_selected = false
	SoundManager.play_sfx("ButtonSounds")
	if PlayerData.game_mode.has(game_mode):
		PlayerData.game_mode.erase(game_mode)
		Game.save_playerdata()
	animation_player.play_backwards("full_anim")
	await animation_player.animation_finished
	animation_player.play_backwards("select_anim")
	await animation_player.animation_finished
	open_mouse()

func has_game_mode_conflicting(now_conflicting: Array):
	if now_conflicting.has(gamemode_card.game_mode_id) and PlayerData.game_mode.has(game_mode):
		erase_game_mode()

func gamemode_selected(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if on_selected == false and on_touch == false:
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			on_touch = true
			show_text = true
			text_show.visible = true
			SoundManager.play_sfx("ButtonSounds2")
			animation_player.play("select_anim")
		elif on_selected == false and on_touch == true:
			show_text = false
			text_show.visible = false
			add_game_mode()
		elif on_selected == true:
			erase_game_mode()
	
	if on_selected == false and event.is_action_pressed("shoot"):
		add_game_mode()
	elif on_selected == true and event.is_action_pressed("shoot"):
		erase_game_mode()
