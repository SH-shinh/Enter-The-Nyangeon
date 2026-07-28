extends PanelContainer

@export_file("*.tscn") var path: String
@export_file("*.tscn") var player: String
@export var player_card: PlayerCard

@onready var card_anim = $AnimationPlayer
@onready var player_p = $%PlayerP
@onready var ps_label: Label = $ColorRect/Node2D/Node2D/Node2D/Label

var on_select: bool = false

var on_touch: bool = false

func _ready():
	card_anim.play("add_card")
	mouse_entered.connect(select_player_card)
	mouse_exited.connect(select_out_player_card)
	gui_input.connect(add_player)
	GameEvents.player_card_selected.connect(mouse_close)
	GameEvents.level_select_out.connect(mouse_open)
	GameEvents.player_card_touch.connect(touch_out_player_card)
	ps_label.text = player_card.id + "_ps_0"

func mouse_open():
	mouse_filter = 0
	if on_select == true:
		card_anim.play("select_out")
		on_select = false
		on_touch = false

func mouse_close():
	mouse_filter = 2

func select_player_card():
	SoundManager.play_sfx("ButtonSounds2")
	card_anim.play("select_card")

func select_out_player_card():
	if on_select == false:
		card_anim.play("select_out")

func touch_out_player_card():
	
	await get_tree().create_timer(0.05).timeout
	
	if on_select == false and on_touch == true:
		on_touch = false
		card_anim.play("select_out")

func play_voice():
	var n = randi_range(0,1)
	if n == 0:
		SoundManager.play_voice(player_card.voice_name, "SelectVoice1")
	else:
		SoundManager.play_voice(player_card.voice_name, "SelectVoice2")

func add_player(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		if on_touch == false:
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			on_touch = true
			SoundManager.play_sfx("ButtonSounds2")
			card_anim.play("select_card")
			
		else:
			SoundManager.play_sfx("ButtonSounds")
			if player != "":
				play_voice()
				on_select = true
				GameEvents.emit_player_card_selected()
				GameEvents.emit_player_card_id(player)
				card_anim.play("select_anim")
				SupportData.reset_game_support()
				await card_anim.animation_finished
				GameEvents.emit_level_select_in()
	
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		if player != "":
			play_voice()
			on_select = true
			GameEvents.emit_player_card_selected()
			GameEvents.emit_player_card_id(player)
			card_anim.play("select_anim")
			SupportData.reset_game_support()
			await card_anim.animation_finished
			GameEvents.emit_level_select_in()
