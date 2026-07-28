extends Area2D

@export var self_body: Node

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D

var body_group: Array

func _ready() -> void:
	self_body.is_jump.connect(on_jump)
	self_body.is_jump_end.connect(jump_end)

func _physics_process(delta: float) -> void:
	if body_group.size() != 0:
		for i in body_group:
			i.velocity += (i.global_position - self_body.global_position).normalized() * i.stats.summoned_speed / max(0.5, i.global_position.distance_to(self.global_position))

func on_jump():
	collision_shape_2d.disabled = true

func jump_end():
	collision_shape_2d.disabled = false

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("Summoned")  and !body_group.has(body) and body != self_body:
		body_group.append(body)
		var collosion_direction = (self_body.position - body.position).normalized()
		self_body.velocity += collosion_direction * self_body.stats.summoned_speed * 0.5

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("Summoned")  and body_group.has(body):
		body_group.remove_at(body_group.find(body))
		body.velocity = body.velocity.limit_length(body.stats.summoned_speed * 0.5)
