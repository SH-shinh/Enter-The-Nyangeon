extends Node2D

@onready var animation_player = $AnimationPlayer
@onready var gpu_particles_2d = $GPUParticles2D

var is_idle:int = 1

func idle_state():
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO
	animation_player.play("RESET")

func active_state():
	is_idle = 0
	self.visible = true
	animation_player.play("new_animation")
	gpu_particles_2d.restart()
	SoundManager.play_sfx("JumpSounds")
