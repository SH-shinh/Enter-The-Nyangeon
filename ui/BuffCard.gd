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
	PoolManager.add_pool("buff_card",self)
	active_state()

func idle_state():
	if PoolManager.buff_box != null:
		self.reparent(PoolManager.buff_box)
	is_idle = 1
	if GameEvents.global_time_count.is_connected(set_value):
		GameEvents.global_time_count.disconnect(set_value)
	player_buff = null
	self.visible = false

func active_state():
	is_idle = 0
	if !GameEvents.global_time_count.is_connected(set_value):
		GameEvents.global_time_count.connect(set_value)
	self.visible = true

func _physics_process(delta):
	if player_buff != null:
		if player_buff.buff_erase_timer != 0:
			buff_icon.value = player_buff.buff_timer.time_left / player_buff.buff_erase_timer
			if player_buff.layer <= 1:
				buff_layer.text = ""
			else:
				buff_layer.text = str(player_buff.layer)

func set_value():
	if player_buff == null:
		if erase_time != 0:
			buff_icon.value = 1 - float(now_time) / float(erase_time)
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
