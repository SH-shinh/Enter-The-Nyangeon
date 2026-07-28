extends Node2D

@onready var pink = $Pink
@onready var blue = $Blue
@onready var yellow = $Yellow

var idle_time: int = 100

var is_idle: int = 1

func _ready():
	PoolManager.add_pool("floor_paint",self)

func idle_state():
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	self.visible = false
	self.global_position = Vector2.ZERO

func clear_pool():
	PoolManager.erase_pool("floor_paint")

func active_state():
	is_idle = 0
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	idle_time = 100
	self.visible = true
	var color_num = randi_range(0,2)
	if color_num == 0:
		emitting_pink()
	elif color_num == 1:
		emitting_blue()
	else:
		emitting_yellow()

func emitting_pink():
	pink.restart()

func emitting_blue():
	blue.restart()

func emitting_yellow():
	yellow.restart()

func time_count():
	if idle_time > 0:
		idle_time -= 1
		if idle_time <= 0:
			idle_state()
