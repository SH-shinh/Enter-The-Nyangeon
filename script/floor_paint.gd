extends Node2D

@onready var pink = $Pink
@onready var blue = $Blue
@onready var yellow = $Yellow

var idle_time: int = 100

var is_idle: int = 1
## 本次播放的颜色索引（0=Pink / 1=Blue / 2=Yellow），供 Maki 彩弹同色校验/调试。
var last_color: int = -1

func _ready():
	PoolManager.add_pool("floor_paint",self)

func idle_state():
	reset_physics_interpolation()
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	self.visible = false
	self.global_position = Vector2.ZERO

func clear_pool():
	PoolManager.erase_pool("floor_paint")

func active_state(color_num: int = -1):
	reset_physics_interpolation()
	is_idle = 0
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	idle_time = 100
	self.visible = true
	if color_num < 0 or color_num > 2:
		color_num = randi_range(0, 2)
	last_color = color_num
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

## 联机通用视觉参数入口：远端克隆按颜色重放（纯表现）。
func network_apply_visual(params: Dictionary) -> void:
	var c = params.get("color", -1)
	active_state(int(c) if (c is int or c is float) else -1)

func time_count():
	if idle_time > 0:
		idle_time -= 1
		if idle_time <= 0:
			idle_state()
