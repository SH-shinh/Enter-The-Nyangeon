extends Node2D

@export var pool_id: String = "bullet_smoke_1"

@onready var animation_player = $AnimationPlayer
@onready var gpu_particles_2d = $GPUParticles2D

var is_idle: int = 0

func _ready():
	PoolManager.add_pool(pool_id,self)

func idle_state():
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO

func active_state():
	is_idle = 0
	self.visible = true

func smoke_reset():
	pass

func smoke_anim():
	if not PoolManager.fx_allowed(&"bullet_smoke"):
		idle_state()
		return
	active_state()
	animation_player.play("new_animation")
	gpu_particles_2d.restart()
