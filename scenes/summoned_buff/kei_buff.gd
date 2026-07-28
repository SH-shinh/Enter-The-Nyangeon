extends Node2D

signal buff_time_out(buff: Buff)

@onready var buff_timer = $BuffTimer

@export var buff: Buff
@export var buff_id: String
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@export var is_remove_by_layer: bool = false

var body: Node
var num: int
var layer: int = 0
var buff_time: float
var is_stop: bool = false

func _ready():
	body = get_parent()
	body.summoned_buff_manager.summoned_buff_added.connect(on_buff_added)

func on_buff_added(summoned_buff: Buff, current_buff: Dictionary):
	
	if summoned_buff.id != buff_id:
		return
	buff_timer.wait_time = buff_erase_timer
	buff_timer.start()
	num = current_buff[buff_id]["quantity"]
	if layer >= buff_layer:
		return
	if is_stop == true:
		return
	layer += 1
	body.stats.summoned_damage_mult_add += buff_value
	body.stats.update_body_ability()

func _on_buff_timer_timeout():
	if is_stop == true:
		return
	if is_remove_by_layer == false:
		body.stats.summoned_damage_mult_add -= ( buff_value * layer )
		layer = 0
	else:
		layer -= 1
	body.stats.update_body_ability()
	if layer <= 0:
		is_stop = true
		buff_time_out.emit(buff)
		queue_free()

func clear_buff():
	if is_stop == true:
		return
	if is_remove_by_layer == false:
		body.stats.summoned_damage_mult_add -= ( buff_value * layer )
		layer = 0
	else:
		layer -= 1
	body.stats.update_body_ability()
	if layer <= 0:
		is_stop = true
		buff_time_out.emit(buff)
		queue_free()
