extends Node2D

@onready var line_2d = $Line2D
@onready var marker_2d = $Marker2D3/Marker2D
@onready var marker_2d_2 = $Marker2D3/Marker2D2
@onready var marker_2d_3 = $Marker2D3
@onready var line_2d_2 = $Line2D2
@onready var line_2d_3 = $Line2D3
@onready var marker2_2d = $Marker2D4/Marker2D
@onready var marker2_2d_2 = $Marker2D4/Marker2D2
@onready var marker_2d_4 = $Marker2D4


func _process(delta):
	
	look_at(get_global_mouse_position())
	
	marker2_2d.position.y = -marker_2d_4.position.x / 2
	marker2_2d_2.position.y = marker_2d_4.position.x / 2
	
	
	line_2d.set_point_position(0, Vector2(marker_2d_3.position.x,-marker_2d.position.y))
	line_2d.set_point_position(1, position)
	line_2d.set_point_position(2, Vector2(marker_2d_3.position.x,marker_2d.position.y))
	#marker_2d_3.position = get_global_mouse_position()
	line_2d_2.set_point_position(0, Vector2(marker_2d_3.position.x,-marker_2d.position.y))
	line_2d_2.set_point_position(1, 0.8 * Vector2(marker_2d_4.position.x,marker2_2d_2.position.y))
	
	line_2d_3.set_point_position(0, Vector2(marker_2d_3.position.x,marker_2d.position.y))
	line_2d_3.set_point_position(1, 0.8 * Vector2(marker_2d_4.position.x,marker2_2d.position.y))
	
	marker_2d_4.global_position = get_global_mouse_position()
	
	
	
	
	pass

func can_see():
	
	visible = true
	var tween = get_tree().create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1,1), 0.1).from(Vector2(0, 0))
	

func not_can_see():
	
	visible = false
