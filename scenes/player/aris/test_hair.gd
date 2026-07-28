extends Line2D

var timer: int = 0
var life_timer: int = 10
@export var p1: Node

func _ready():
	clear_points()

func _process(delta):
	add_point(p1.position )
	timer += 1
	if timer >= life_timer:
		remove_point(0)
		timer -= 1
