extends Node2D

@export var target_node: Node
@export var warring_target_position: Vector2

@onready var arrow_icon = $arrow_icon
@onready var label = $Label
@onready var animation_player = $AnimationPlayer

var camera_zoom: Vector2

func _ready():
	GameEvents.get_player.connect(get_player_camera)

func hide_arrow():
	if self.visible == false:
		return
	animation_player.play("RESET")
	self.visible = false

func get_player_camera():
	warring_target_position = target_node.target.global_position
	camera_zoom = get_viewport().get_camera_2d().zoom

func _process(_delta):
	if target_node == null:
		return
	
	if target_node.visible == false:
		hide_arrow()
		return
	else:
		if self.visible == false:
			animation_player.play("warring_anim")
			self.visible = true
	
	var target_screen_position = ( warring_target_position - get_camera_rect().position ) * camera_zoom
	
	if target_on_screen():
		global_position = target_screen_position
		arrow_icon.rotation = PI/2
		label.position.x = -29
		label.position.y = -19
	else:
		set_screen_position(target_screen_position)
		rotate_to_target()

func get_camera_rect():
	var pos = get_viewport().get_camera_2d().get_screen_center_position()
	var screen_size = get_viewport_rect().size / camera_zoom
	
	return Rect2( pos - screen_size / 2, screen_size )

func target_on_screen():
	return get_camera_rect().has_point(warring_target_position)

func set_screen_position(target_screen_position: Vector2):
	var screen_size = get_viewport_rect().size
	var borderoffset = 10
	var target_position = target_screen_position
	
	if target_position.x < borderoffset:
		target_position.x = borderoffset
	if target_position.x > screen_size.x - borderoffset:
		target_position.x = screen_size.x - borderoffset
	if target_position.y < borderoffset:
		target_position.y = borderoffset
	if target_position.y > screen_size.y - borderoffset:
		target_position.y = screen_size.y - borderoffset
	
	global_position = target_position
	
	var text_offset_x = ( -target_position.x / 300 ) + 1
	var text_offset_y = ( -target_position.y / 170 ) + 1
	label.position.x = 29 * text_offset_x - 29
	label.position.y = 9 * text_offset_y - 9

func rotate_to_target():
	var current_position = get_viewport().get_camera_2d().get_screen_center_position()
	var direction = ( warring_target_position - current_position ).normalized()
	
	arrow_icon.rotation = direction.angle()
