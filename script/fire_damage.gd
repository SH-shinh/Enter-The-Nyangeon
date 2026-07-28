extends Node2D

var fire_num: int = 1
var fire_damage: int = 0
var damage_knockback: int = 0
var hit_direction: Vector2
var value: Array
@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

func _ready():
	value = [buff_layer, buff_value, buff_erase_timer]
	pass

func _on_area_2d_body_entered(body):
	if body.is_in_group("Enemy"):
		
		hit_direction = (body.position - position).normalized()
		
		for i in fire_num:
			body.enemy_buff_manager.apply_buff(enemy_buff, value)
		
		body.hurt_damage = fire_damage
		body.hurt_knockback = damage_knockback
		body.hurt_direction = hit_direction
		body.is_fire_hit = true
		body.emit_signal("is_hurt")

func _on_timer_timeout():
	queue_free()
