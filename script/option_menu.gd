extends Control
class_name OptionMenu

@export var option_id: String
@onready var animation_player = $AnimationPlayer

var shown: bool = false

func menu_show():
	shown = true
	animation_player.play("option_in")

func menu_hide():
	if not shown:
		return
	shown = false
	animation_player.play_backwards("option_in")
