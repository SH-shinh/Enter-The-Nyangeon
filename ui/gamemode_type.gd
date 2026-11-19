extends PanelContainer

signal selection_changed(game_mode_id: String, selected: bool)

const KIND_MARK_ENEMY := Color(0.815686, 0.701961, 0.0235294, 1.0)
const KIND_MARK_FIELD := Color(0.16, 0.78, 0.9, 1.0)
const KIND_MARK_PLAYER := Color(0.92, 0.27, 0.35, 1.0)

@export var gamemode_card: GameMode
@export var gamemode_conflicting: Array[String]

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var label: Label = $VBoxContainer/Label
@onready var texture_rect: TextureRect = $VBoxContainer/TextureRect
@onready var kind_mark: ColorRect = $VBoxContainer/TextureRect2/ColorRect
@onready var kind_mark_accent: ColorRect = $VBoxContainer/TextureRect2/ColorRect/ColorRect

var game_mode: String
var on_selected: bool = false
var on_touch: bool = false
var _tooltip: HoverTooltipBinding
var _changing := false
var _input_open := true
var _change_sequence: int = 0

func _ready() -> void:
	_tooltip = HoverTooltipBinding.bind(self, _tooltip_content, func(): return _input_open, func(): on_touch = false)
	GameEvents.player_card_touch.connect(touch_out)
	mouse_entered.connect(_mouse_enter)
	mouse_exited.connect(_mouse_exit)
	gui_input.connect(gamemode_selected)
	GameEvents.gamemode_conflicting.connect(has_game_mode_conflicting)
	focus_entered.connect(_mouse_enter)
	focus_exited.connect(_mouse_exit)

func _process(delta: float) -> void:
	if label.size.x > 39:
		var now_font = label.get("theme_override_font_sizes/font_size")
		if now_font > 1:
			now_font -= 1
			label.set("theme_override_font_sizes/font_size", now_font)

func get_gamemode_card():
	gamemode_conflicting = gamemode_card.gamemode_conflicting
	label.text = str(gamemode_card.game_mode_name) + "_id"
	game_mode = gamemode_card.game_mode_id
	texture_rect.texture = gamemode_card.game_mode_icon
	var mark_color := KIND_MARK_ENEMY
	if gamemode_card.is_field_chip():
		mark_color = KIND_MARK_FIELD
	elif gamemode_card.is_player_chip():
		mark_color = KIND_MARK_PLAYER
	kind_mark.color = mark_color
	kind_mark_accent.color = mark_color
	if PlayerData.game_mode.has(game_mode):
		on_selected = true
		animation_player.play("full_anim")

func open_mouse():
	mouse_filter = Control.MOUSE_FILTER_STOP if _input_open else Control.MOUSE_FILTER_IGNORE

func set_interactive(enabled: bool) -> void:
	_input_open = enabled
	if not enabled:
		_tooltip.dismiss()
	focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	if enabled and not _changing:
		open_mouse()
	else:
		close_mouse()

func close_mouse():
	mouse_filter = 2

func _mouse_enter() -> void:
	if _changing:
		return
	if on_selected == false:
		SoundManager.play_sfx("ButtonSounds2")
		animation_player.play("select_anim")
	else:
		SoundManager.play_sfx("ButtonSounds2")
		animation_player.play("full_select")

func _mouse_exit():
	if has_focus():
		return
	if _changing:
		return
	if on_selected == false:
		animation_player.play_backwards("select_anim")
	else:
		animation_player.play_backwards("full_select")

func touch_out() -> void:
	var had_touch := on_touch
	_tooltip.dismiss()
	if not on_selected and had_touch:
		animation_player.play_backwards("select_anim")

func add_game_mode():
	_change_sequence += 1
	var sequence := _change_sequence
	_changing = true
	close_mouse()
	on_selected = true
	SoundManager.play_sfx("ButtonSounds")
	if !PlayerData.game_mode.has(game_mode):
		PlayerData.game_mode.append(game_mode)
		GameEvents.emit_gamemode_conflicting(gamemode_conflicting)
		Game.save_playerdata()
		selection_changed.emit(game_mode, true)
	animation_player.play("full_anim")
	await animation_player.animation_finished
	if sequence != _change_sequence:
		return
	open_mouse()
	_changing = false
	if has_focus():
		_mouse_enter()

func erase_game_mode():
	_change_sequence += 1
	var sequence := _change_sequence
	_changing = true
	close_mouse()
	on_selected = false
	SoundManager.play_sfx("ButtonSounds")
	if PlayerData.game_mode.has(game_mode):
		PlayerData.game_mode.erase(game_mode)
		Game.save_playerdata()
		selection_changed.emit(game_mode, false)
	animation_player.play_backwards("full_anim")
	await animation_player.animation_finished
	if sequence != _change_sequence:
		return
	animation_player.play_backwards("select_anim")
	await animation_player.animation_finished
	if sequence != _change_sequence:
		return
	open_mouse()
	_changing = false
	if has_focus():
		_mouse_enter()

func has_game_mode_conflicting(now_conflicting: Array):
	if now_conflicting.has(gamemode_card.game_mode_id) and PlayerData.game_mode.has(game_mode):
		erase_game_mode()

func gamemode_selected(event: InputEvent):
	if not _input_open:
		return
	if event is InputEventMouseMotion and focus_mode != Control.FOCUS_NONE and event.relative != Vector2.ZERO and event.device != InputEvent.DEVICE_ID_EMULATION:
		grab_focus()
		return
	if event.is_action_pressed("ui_accept") and has_focus():
		accept_event()
		if event.is_echo() or _changing:
			return
		if on_selected:
			erase_game_mode()
		else:
			add_game_mode()
		return
	if _changing:
		return
	if event is InputEventScreenTouch:
		if not _tooltip.tapped(event):
			return
		if on_selected == false and on_touch == false:
			GameEvents.emit_player_card_touch()
			on_touch = true
			_tooltip.preview("touch", event.index)
			SoundManager.play_sfx("ButtonSounds2")
			animation_player.play("select_anim")
		elif on_selected == false and on_touch == true:
			_tooltip.dismiss()
			add_game_mode()
		elif on_selected == true:
			erase_game_mode()
	
	if on_selected == false and event.is_action_pressed("shoot"):
		add_game_mode()
	elif on_selected == true and event.is_action_pressed("shoot"):
		erase_game_mode()

func _tooltip_content() -> Array:
	if gamemode_card == null:
		return []
	return [{"text": str(gamemode_card.game_mode_name) + "_id", "role": "title"}, {"text": str(gamemode_card.game_mode_name) + "_description", "optional": true}]
