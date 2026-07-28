extends Node2D

signal buff_time_out(buff: Buff)

@onready var buff_timer = $BuffTimer

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

var debt_value: Array[float] = [0, 0.9, 0.8, 0.6, 0.4, 0.01]
var coin_get: Array[float] = [0, 0.2, 0.4, 0.8, 1.5, 3]

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.player_buff_added.connect(on_buff_added)
	GameEvents.player_buff_clear.connect(clear_buff)

func on_buff_added(player_buff: Buff, current_buff: Dictionary):
	if player_buff.id != buff_id:
		return
	buff_timer.wait_time = 999
	buff_timer.start()
	num = current_buff[buff_id]["quantity"]
	
	if layer >= buff_layer:
		return
	if is_stop == true:
		return
	if layer < 1:
		PlayerData.ability_mult = debt_value[buff_value]
		if buff_erase_timer > 0:
			PlayerData.coin_mult_add += coin_get[buff_value]
		PlayerData.update_player_ability()
	layer += 1


func _on_buff_timer_timeout():
	if is_stop == true:
		return
	if is_remove_by_layer == false:
		PlayerData.ability_mult = 1
		if buff_erase_timer > 0:
			PlayerData.coin_mult_add -= coin_get[buff_value]
		layer = 0
	else:
		PlayerData.ability_mult = 1
		if buff_erase_timer > 0:
			PlayerData.coin_mult_add -= coin_get[buff_value]
		layer -= 1
	PlayerData.update_player_ability()
	if layer <= 0:
		is_stop = true
		buff_time_out.emit(buff)
		queue_free()

func erase_buff():
	if is_stop == true:
		return
	is_stop = true
	PlayerData.ability_mult = 1
	if buff_erase_timer > 0:
		PlayerData.coin_mult_add -= coin_get[buff_value]
	layer = 0
	PlayerData.update_player_ability()
	if layer <= 0:
		buff_time_out.emit(buff)
		queue_free()

func clear_buff():
	if is_stop == true:
		return
	is_stop = true
	PlayerData.ability_mult = 1
	if buff_erase_timer > 0:
		PlayerData.coin_mult_add -= coin_get[buff_value]
	layer = 0
	PlayerData.update_player_ability()
	if layer <= 0:
		buff_time_out.emit(buff)
		queue_free()
