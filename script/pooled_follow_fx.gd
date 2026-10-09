class_name PooledFollowFx
extends Node2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

var target: Node
var is_idle: int = 1

func _ready() -> void:
	PoolManager.add_pool(_pool_key(), self)

# 子类覆写：返回对象池 key
func _pool_key() -> String:
	return name.to_snake_case()

func idle_state() -> void:
	is_idle = 1
	global_position = Vector2.ZERO
	target = null
	visible = false

func _physics_process(_delta: float) -> void:
	if is_idle == 1:
		return
	if target != null and is_instance_valid(target):
		global_position = target.global_position
	else:
		idle_state()

func follow_body(body: Node) -> void:
	target = body

func play_anim() -> void:
	is_idle = 0
	visible = true
	gpu_particles_2d.restart()
	if target != null and is_instance_valid(target):
		global_position = target.global_position
	animation_player.play("new_animation")
