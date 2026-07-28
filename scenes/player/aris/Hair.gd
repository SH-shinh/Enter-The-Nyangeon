extends Node2D

@export var player: Node
@export var amount : int = 6
@export var offset_0: Array[Vector2]
@export var offset_x: Array[Vector2]
@export_range(0.01, 0.99) var k : float = .1
@export var col : Color = Color("ff5881")
@export var startRadius : float = 10
@export var endRadius : float = 5

var points_a: Dictionary
var C : Array[Color]
var C_b : Array[Color]
var anchor : float

var hight: bool = false

func _ready():
	for i in offset_x.size():
		var group: Array[Vector2]
		for x in range(amount):
			group.push_back(Vector2.ZERO)
		points_a[i] = group
	
	for i in range(4):
		C.push_back(col)
		C_b.push_back(Color(0,0,0))

func _draw():
	for x in offset_x.size():
	
		draw_circle(points_a[x][0], startRadius, col)
		
		for i in range(1, amount):
			var R : float= lerp(startRadius, endRadius, float(i-1)/(amount - 1))
			var r : float = lerp(startRadius, endRadius, float(i)/(amount - 1))
			draw_circle(points_a[x][i], r, col)
			var p1 = points_a[x][i-1]
			var p2 = points_a[x][i]
			var dir : Vector2 = (p2 - p1).normalized()
			var d = (p1 - p2).length()
			var theta = asin(sqrt(d*d - (R-r) * (R-r)) / d)
			var P : Array[Vector2]= [
				points_a[x][i-1] + dir.rotated(theta) * R, 
				points_a[x][i] + dir.rotated(theta) * r, 
				points_a[x][i] + dir.rotated(-theta) * r, 
				points_a[x][i-1] + dir.rotated(-theta) * R, 
			]
			draw_polygon(P, C)

func _physics_process(delta):
	
	anchor = player.sprite_2d.position.y + 17
	for x in offset_x.size():
		points_a[x][0].x = offset_0[x].x
		points_a[x][0].y = anchor + offset_0[x].y
	for x in offset_x.size():
		
		for i in range(1, amount): 
			points_a[x][i].x = points_a[x][i].x + (points_a[x][i-1].x + offset_x[x].x + 0.5 * offset_x[x].x * sin(Time.get_ticks_msec() * 0.01) - points_a[x][i].x) * (k + 0.5 / (i * i)) - player.velocity.normalized().x * 0.7
			points_a[x][i].y = points_a[x][i].y + (points_a[x][i-1].y + offset_x[x].y - points_a[x][i].y) * (k + 0.5 / (i * i)) - player.velocity.normalized().y * 0.7
			points_a[x][i].y = min(points_a[x][i].y , 17)
	queue_redraw()
