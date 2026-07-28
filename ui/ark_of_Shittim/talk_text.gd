extends Node2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var label: Label = $PanelContainer/Label
@onready var panel_container: PanelContainer = $PanelContainer

func talk_in(talk_text: String, text_color: Color, outline_color: Color):
	label.text = tr(talk_text)
	label.set("theme_override_colors/font_color", text_color)
	label.set("theme_override_colors/font_outline_color", outline_color)
	panel_container.material.set_shader_parameter("outline_color", outline_color)
	animation_player.play("text_in")

func talk_out():
	animation_player.play_backwards("text_in")
	await animation_player.animation_finished
	queue_free()
