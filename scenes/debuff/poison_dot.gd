extends Node2D

@onready var animation_player = $AnimationPlayer
@onready var gpu_particles_2d = $GPUParticles2D

var target: Node

var is_idle: int = 1

func _ready():
	PoolManager.add_pool("poison", self)

func idle_state():
	is_idle = 1
	self.global_position = Vector2.ZERO
	target = null
	self.visible = false
	

func _physics_process(_delta):
	
	if is_idle == 1:
		return
	
	if target != null:
		self.global_position = target.global_position
	else:
		idle_state()

func follow_body(body: Node):
	target = body

func play_anim():
	is_idle = 0
	self.visible = true
	gpu_particles_2d.restart()
	
	if target != null:
		self.global_position = target.global_position
	
	animation_player.play("new_animation")
