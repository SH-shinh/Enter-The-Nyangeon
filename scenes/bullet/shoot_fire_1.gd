extends Node2D

@onready var gpu_particles_2d = $GPUParticles2D
@onready var gpu_particles_2d_3 = $GPUParticles2D3
@onready var gpu_particles_2d_2 = $GPUParticles2D2
@onready var gpu_particles_2d_4 = $GPUParticles2D4

func active_state():
	gpu_particles_2d.restart()
	gpu_particles_2d_3.restart()
	gpu_particles_2d_4.restart()
	gpu_particles_2d_2.restart()
