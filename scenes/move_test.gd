extends Node2D

var dir
var dir2
var dir_v

var speed = 60
var speed_time = 3.0
var accel

var player

@export var r_speed: int = 1
var acceleration: Vector2 = Vector2.ZERO

@onready var body: CharacterBody2D = %CharacterBody2D
@onready var sprite_2d: Sprite2D = %Sprite2D
@onready var sprite_2d_2: Sprite2D = %Sprite2D2

#ins.rotation = direction.angle()


func _ready():
	#player = get_tree().get_first_node_in_group("Player")
	pass
	
func _process(delta):
	dir = get_global_mouse_position()
	##dir = player.global_position
	dir2 = (dir - body.global_position).normalized()
	##speed_time = body.global_position.distance_to(dir).normalized()
	#speed = body.global_position.distance_to(dir) * 1.3 * body.global_position.distance_to(dir) / 100
	accel = speed / speed_time
	dir_v = dir2 * speed
	
	#if body.global_position.distance_to(dir) < 1:
		#pass
		##dir_v = -dir2
	#elif body.global_position.distance_to(dir) > 80:
		#dir_v = dir2
	#else:
		##speed = 40
		#dir_v.x = dir2.y
		#dir_v.y = -dir2.x
	
	#print(dir_v.x)
	#print(dir_v.y)
	
	
	
	#sprite_2d_2.rotation = move_toward(sprite_2d_2.rotation + PI, dir_v.angle() + PI, 0.5 * delta)
	
	#velocity = Vector2.RIGHT.rotated(dir.rotation) * 50
	#
	body.velocity.x = move_toward(body.velocity.x, dir_v.x, accel * delta)
	body.velocity.y = move_toward(body.velocity.y, dir_v.y, accel * delta)
	#body.velocity = Vector2.RIGHT * speed
	acceleration += (dir_v - body.velocity).normalized() * r_speed
	body.velocity += acceleration * delta
	body.velocity = body.velocity.limit_length(speed)
	
	sprite_2d.v = body.velocity.normalized().angle()
	sprite_2d_2.v = dir2.angle()
	
	body.move_and_slide()
	#
	
	#$CharacterBody2D/Marker2D.rotation = body.velocity.normalized().angle()
