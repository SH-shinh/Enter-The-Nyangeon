extends CanvasLayer

signal level_is_selected
signal player_selected

@onready var animation_player = $AnimationPlayer

var player: String

func _ready():
	GameEvents.player_card_id.connect(get_player_id)
	GameEvents.level_select_in.connect(level_menu_in)

func _unhandled_input(event):
	if event.is_action_pressed("pause"):
		SoundManager.play_sfx("UISounds2")
		GameEvents.emit_level_select_out()
		animation_player.play("RESET")

func get_player_id(player_id: String):
	player = player_id

func emit_player_selected():
	player_selected.emit()

func level_menu_in():
	SoundManager.play_sfx("UISounds1")
	animation_player.play("select_in")
