extends PanelContainer

## 敌人头顶的 buff 卡片（图标 + 层数）。
## 性能：**不要用 `_physics_process` 每物理帧刷**——160 只敌人 × 1~3 张卡 × 60Hz 是纯 C++ 绘制开销。
## 现在由 `GameEvents.global_time_count`（10Hz）驱动 `set_value()`，且图标/文字只在变化时写。

@onready var buff_icon = $%BuffIcon
@onready var buff_layer = %BuffLayer

var player_buff
var buff_id: String

var now_time: int
var erase_time: int
var layer: int

var is_idle: int = 1

# 上次写入的值：图标进度 1/128 内不重写；文字判等，避免无意义 canvas 重绘。
var _last_icon_value: float = -2.0
var _last_layer_text: String = "<unset>"

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
	# 归池/复用后强制下一拍重写，避免残留上一条 buff 的图标/层数。
	_last_icon_value = -2.0
	_last_layer_text = "<unset>"
	set_physics_process(false)
	if !GameEvents.global_time_count.is_connected(set_value):
		GameEvents.global_time_count.connect(set_value)
	self.visible = true
	set_value()

## 10Hz（global_time_count）刷新一次：图标进度 + 层数文字。
func set_value():
	var icon_value: float = 1.0
	var layer_text: String = ""
	if player_buff != null:
		if player_buff.buff_erase_timer != 0:
			icon_value = float(player_buff.buff_timer.time_left) / float(player_buff.buff_erase_timer)
		var lv: int = int(player_buff.layer)
		if lv > 1:
			layer_text = str(lv)
	else:
		if erase_time != 0:
			icon_value = 1.0 - float(now_time) / float(erase_time)
		if layer > 1:
			layer_text = str(layer)
	_write_icon_value(clampf(icon_value, 0.0, 1.0))
	_write_layer_text(layer_text)

func _write_icon_value(v: float) -> void:
	if absf(v - _last_icon_value) < 1.0 / 128.0:
		return
	_last_icon_value = v
	buff_icon.value = v

func _write_layer_text(txt: String) -> void:
	if txt == _last_layer_text:
		return
	_last_layer_text = txt
	buff_layer.text = txt

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
