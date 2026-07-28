extends CharacterBody2D

signal player_enter(ball: Node)
signal player_exit(ball: Node)

@export var test_menu: Node
@export var menu_name: String

const  MAX_SPEED = 100
const  ACCELERATION = MAX_SPEED / 1.5
var direction = Vector2.ZERO
var on_chose = false

@onready var sprite_2d = $Sprite2D
@onready var push_sounds = $PushSounds
@onready var camera_marker: Marker2D = $CameraMarker

func _ready() -> void:
	sprite_2d.frame = randi_range(0, 19)

func _physics_process(delta: float) -> void:
	
	velocity.x = move_toward(velocity.x, 0, ACCELERATION * delta)
	velocity.y = move_toward(velocity.y, 0, ACCELERATION * delta)
	sprite_2d.rotation += velocity.x / 720
	sprite_2d.speed_scale = - velocity.y / 24
	
	if on_chose == true:
		sprite_2d.material.set_shader_parameter("outline_width",1)
		if Input.is_action_just_pressed("use") :
			_show_menu()
	else:sprite_2d.material.set_shader_parameter("outline_width",0)
	
	var collisionResult = move_and_collide(velocity * delta)
	if collisionResult :
		velocity = velocity.bounce(collisionResult.get_normal())
	move_and_slide()

func _show_menu():
	if test_menu.visible == false:
		self.velocity = Vector2.ZERO
		GameEvents.emit_camera_move(camera_marker, false)
		test_menu.show_menu()

func _on_push_box_body_entered(body):
	
	if body.is_in_group("Player"):
		if body.sprite_2d.position.y == -17:
			push_sounds.play()
			var push_V = max( abs( body.velocity.x), abs( body.velocity.y) ) / 2
			self.velocity = (self.position - body.position ).normalized() * push_V
			body.velocity = (body.position - self.position).normalized() * MAX_SPEED
	
	if body.is_in_group("Capsule"):
		self.velocity = (self.position - body.position ).normalized() * MAX_SPEED / 3
		body.velocity = (body.position - self.position).normalized() * MAX_SPEED / 3

func _on_pick_box_body_entered(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_enter.emit(self)

func _on_pick_box_body_exited(body: Node2D) -> void:
	if body.is_in_group("Player"):
		player_exit.emit(self)


func _on_panel_container_gui_input(event: InputEvent) -> void:
	if on_chose == true:
		if event as InputEventScreenTouch and event.pressed:
			_show_menu()
