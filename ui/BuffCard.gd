extends PanelContainer

@onready var buff_icon = $%BuffIcon
@onready var buff_layer = %BuffLayer

var player_buff
var buff_id: String

var now_time: int
var erase_time: int
var layer: int

var is_idle: int = 1

func _ready():
	active_state()

func idle_state():
	is_idle = 1
	set_physics_process(false)
	if GameEvents.global_time_count.is_connected(set_value):
		GameEvents.global_time_count.disconnect(set_value)
	player_buff = null
	self.visible = false

func release_to_pool():
	idle_state()
	var box = PoolManager.buff_box
	if box != null and is_instance_valid(box) and get_parent() != box:
		self.reparent(box)
	PoolManager.push_idle_buff_card(self)

func active_state():
	is_idle = 0
	set_physics_process(true)
	if !GameEvents.global_time_count.is_connected(set_value):
		GameEvents.global_time_count.connect(set_value)
	self.visible = true

func _physics_process(_delta):
	if player_buff != null:
		if player_buff.buff_erase_timer != 0:
			buff_icon.value = player_buff.buff_timer.time_left / player_buff.buff_erase_timer
		else:
			buff_icon.value = 1
		
		if player_buff.layer <= 1:
			buff_layer.text = ""
		else:
			buff_layer.text = str(player_buff.layer)

func set_value():
	if player_buff == null:
		if erase_time != 0:
			buff_icon.value = 1 - float(now_time) / float(erase_time)
		else:
			buff_icon.value = 1
		
		if layer <= 1:
			buff_layer.text = ""
		else:
			buff_layer.text = str(layer)

func set_buff_card(buff:Buff):
	buff_icon.texture_progress = buff.icon
	buff_id = buff.id

func get_player_buff(add_buff: Node):
	player_buff = add_buff
	player_buff.buff_time_out.connect(buff_box_free)

func clear_card():
	idle_state()

func buff_box_free(_buff: Buff):
	if player_buff.buff_time_out.is_connected(buff_box_free):
		player_buff.buff_time_out.disconnect(buff_box_free)
	idle_state()
