extends Node2D

signal buff_time_out(buff: Buff)

@onready var buff_timer = $BuffTimer
@onready var dot_timer: Timer = $DotTimer

@export var buff: Buff
@export var buff_id: String
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@export var is_remove_by_layer = false

var num: int
var layer: int = 0
var is_stop: bool = false
var player: Node

func _ready():
	dot_timer.timeout.connect(dot_damage)
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.player_buff_added.connect(on_buff_added)
	GameEvents.player_buff_clear.connect(clear_buff)

func on_buff_added(player_buff: Buff, current_buff: Dictionary):
	if player_buff.id != buff_id:
		return
	buff_timer.wait_time = buff_erase_timer
	buff_timer.start()
	num = current_buff[buff_id]["quantity"]
	
	if layer >= buff_layer:
		return
	if is_stop == true:
		return
	dot_timer.start()
	layer += 1
	dot_damage()

func dot_damage():
	if player != null:
		self.position.y = player.sprite_2d.position.y + 15
		player.hurt_damage = buff_value
		player.hurt_knockback = 0
		player.is_buff_hurt = true
		player.emit_signal("is_hurt")

func _on_buff_timer_timeout():
	if is_stop == true:
		return
	if is_remove_by_layer == false:
		for i in layer:
			pass
		layer = 0
	else:
		pass
		layer -= 1
	if layer <= 0:
		is_stop = true
		buff_time_out.emit(buff)
		queue_free()

func erase_buff():
	if is_stop == true:
		return
	is_stop = true
	pass
	layer = 0
	if layer <= 0:
		buff_time_out.emit(buff)
		queue_free()

func clear_buff():
	if is_stop == true:
		return
	is_stop = true
	pass
	layer = 0
	if layer <= 0:
		buff_time_out.emit(buff)
		queue_free()
