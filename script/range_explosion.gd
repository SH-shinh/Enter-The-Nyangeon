extends Node2D

@onready var gpu_particles_2d_3 = $GPUParticles2D3
@onready var animation_player = $Node2D/AnimationPlayer

func play_anim():
	animation_player.play("new_animation")
	gpu_particles_2d_3.restart()
