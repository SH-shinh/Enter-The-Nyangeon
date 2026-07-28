extends CharacterBody2D

@export var body_id: String

@onready var gpu_particles_2d = $GPUParticles2D
@onready var timer = $Timer
@onready var timer_2 = $Timer2

var is_idle: int = 1

const accel: int = 1200

func _ready():
	PoolManager.add_pool(body_id,self)

func idle_state():
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO
	gpu_particles_2d.emitting = false
	timer.stop()

func active_state():
	is_idle = 0
	self.visible = true
	gpu_particles_2d.restart()
	timer.start()

func _physics_process(delta):
	if is_idle == 1:
		return
	velocity.y += accel * delta
	velocity.x *= 0.98
	move_and_slide()

func _on_timer_timeout():
	gpu_particles_2d.emitting = false
	timer_2.start()


func _on_timer_2_timeout():
	idle_state()
