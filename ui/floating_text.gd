extends Node2D

@onready var label = $Node2D/Label
@onready var animation_player = $AnimationPlayer
@onready var animation_player_2 = $AnimationPlayer2


var color_1: Color
var color_2: Color
#var tween: Tween
#var scale_tween: Tween
var is_idle:int = 1

var _last_color: Color = Color(-1, -1, -1, -1)
var _last_size: int = -1

func _ready():
	PoolManager.add_pool("floating_text", self)

func idle_state():
	is_idle = 1
	animation_player_2.stop()
	global_position = Vector2.ZERO
	reset()

func reset():
	visible = false
	animation_player.stop()

func start(text: String):
	
	is_idle = 0
	visible = true
	label.text = text
	animation_player_2.play("new_animation")

func set_style(text_color: Color, text_size: int):
	if text_color != _last_color:
		label.set("theme_override_colors/font_color", text_color)
		_last_color = text_color
	if text_size != _last_size:
		label.set("theme_override_font_sizes/font_size", text_size)
		_last_size = text_size

func play_anim(color_a: Color, color_b: Color):
	color_1 = color_a
	color_2 = color_b
	animation_player.play("color_anim")

func set_color_1():
	label.set("theme_override_colors/font_color", color_1)

func set_color_2():
	label.set("theme_override_colors/font_color", color_2)
