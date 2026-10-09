extends Node2D

@onready var animation_player = $AnimationPlayer

func _ready():
	visible = false

func start():
	visible = true
	animation_player.play("new_animation")

func stop():
	animation_player.stop()
	visible = false
