extends CharacterBody2D

var gravity := ProjectSettings.get("physics/2d/default_gravity") as float
@onready var hair = preload("res://scenes/player/aris/aris_hair.tscn")

var ACCELERATION = 750

var look_dir = null

var player_stop: bool = false

@onready var graphics = $CanvasGroup/Graphics
@onready var sprite_2d = $CanvasGroup/Graphics/AnimatedSprite2D


func _process(delta):
	#graphics.position = self.position
	move(0.0, delta, ACCELERATION, 150)
	set_player_lookat(get_global_mouse_position())

func move(gravity: float, delta: float, ACCELERATION: float ,MAX_SPEED: float ) -> void:
	
	var movement_vector = get_movement_vector()
	var direction = movement_vector.normalized()
	if player_stop == false:
		velocity.x = move_toward(velocity.x, direction.x * 150, ACCELERATION * delta)
		velocity.y = move_toward(velocity.y, direction.y * 150, ACCELERATION * delta)
	move_and_slide()

func get_movement_vector():
	var x_movement = Input.get_axis("move_left", "move_right")
	var y_movement = Input.get_axis("move_up", "move_down")
	
	return Vector2(x_movement, y_movement)

func set_player_lookat(dir):
	if dir != null:
		look_dir = sprite_2d.global_position + (dir * 1000)
		if dir.x > position.x :
			graphics.scale.x = 1

		elif dir.x < position.x :
			graphics.scale.x = -1
			

	else:
		look_dir = null
