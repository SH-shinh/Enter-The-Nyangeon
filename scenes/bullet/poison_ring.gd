extends Node2D

var player: Node
var poison_damage: int = 0
var value: Array
@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var collision_shape_2d: CollisionShape2D = $Area2D/CollisionShape2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

func idle_state():
	poison_damage = 0
	self.global_position = Vector2.ZERO
	self.visible = false
	collision_shape_2d.disabled = true
	gpu_particles_2d.emitting = false

func active_state():
	self.visible = true
	animation_player.play("new_animation")

func gpu_emitting():
	gpu_particles_2d.emitting = true
	gpu_particles_2d.restart()

func _on_area_2d_body_entered(body: Node2D) -> void:
	if body.is_in_group("Enemy"):
		body.is_poison_hit = true
		buff_value = poison_damage
		value = [buff_layer, buff_value, buff_erase_timer]
		body.enemy_buff_manager.apply_buff(enemy_buff, value)
