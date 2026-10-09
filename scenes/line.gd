extends Line2D

@export var width_f: float

var timer: int = 0
var life_timer: int = 10
var p1: Node
var scale_mult: float = 1
# 空闲时停物理：池中大量空闲拖尾不再每帧回调（不改更新频率）
var is_idle: bool = false:
	set(v):
		is_idle = v
		set_physics_process(not v)

func _ready():
	p1 = get_parent()
	clear_points()
	update_width()

func reset():
	clear_points()
	timer = 0

func _physics_process(_delta):
	if is_idle == false:
		add_point(p1.position )
		timer += 1
		if timer >= life_timer:
			remove_point(0)
			timer -= 1

func update_width():
	self.set_width( width_f * scale_mult)
