extends Node2D

@onready var animation_player = $AnimationPlayer

func play_anim():
	animation_player.play("neddle_anim")
	SoundManager.play_sfx("EquipSounds6")
