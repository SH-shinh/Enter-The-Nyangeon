extends Node2D

@onready var gpu_particles_2d = $GPUParticles2D
@onready var gpu_particles_2d_2 = $GPUParticles2D2
@onready var gpu_particles_2d_3: GPUParticles2D = $GPUParticles2D3
@onready var animation_player = $AnimationPlayer

var is_idle: int = 0

func _ready():
	PoolManager.add_pool("cannon_flash_1",self)

func idle_state():
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO

func active_state():
	is_idle = 0
	self.visible = true
	animation_player.play("new_animation")
	gpu_particles_2d.restart()
	gpu_particles_2d_2.restart()
