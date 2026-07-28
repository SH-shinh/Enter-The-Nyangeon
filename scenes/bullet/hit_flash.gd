extends Node2D

@export var pool_id: String
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

var is_idle: int = 1

func _ready() -> void:
	PoolManager.add_pool(pool_id,self)

func idle_state():
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO

func active_state():
	is_idle = 0
	self.visible = true
	animation_player.play("new_animation")
	gpu_particles_2d.restart()
