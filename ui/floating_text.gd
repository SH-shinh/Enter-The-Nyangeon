extends Node2D

@onready var label = $Node2D/Label
@onready var animation_player = $AnimationPlayer
@onready var animation_player_2 = $AnimationPlayer2


var color_1: Color
var color_2: Color
#var tween: Tween
#var scale_tween: Tween
var is_idle:int = 1

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

# 始终写入：不能靠“与上次相同就跳过”的缓存——本节点来自共享池，
# 而拾取物（pyroxenes / player.add_text）会直接改 Label 的 font_color/font_size
# 或播放颜色动画，导致缓存与实际不一致；跳过会残留白色 / 24 号（见 LEARNINGS）。
func set_style(text_color: Color, text_size: int):
	label.set("theme_override_colors/font_color", text_color)
	label.set("theme_override_font_sizes/font_size", text_size)

func play_anim(color_a: Color, color_b: Color):
	color_1 = color_a
	color_2 = color_b
	animation_player.play("color_anim")

func set_color_1():
	label.set("theme_override_colors/font_color", color_1)

func set_color_2():
	label.set("theme_override_colors/font_color", color_2)
