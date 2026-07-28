extends Node2D

@onready var animation_player = $AnimationPlayer
@onready var gpu_particles_2d_2 = $GPUParticles2D2
@onready var gpu_particles_2d_3 = $GPUParticles2D3
@onready var gpu_particles_2d_5 = $GPUParticles2D5
@onready var gpu_particles_2d_4 = $GPUParticles2D4


var is_idle: int = 1


func _ready():
	PoolManager.add_pool("small_explosion",self)

func idle_state():
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO

func active_state():
	is_idle = 0
	self.visible = true
	animation_player.play("new_animation")
	gpu_particles_2d_2.restart()
	gpu_particles_2d_3.restart()
	gpu_particles_2d_5.restart()
	gpu_particles_2d_4.restart()
