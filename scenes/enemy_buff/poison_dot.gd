extends Node2D

signal buff_time_out(buff: Buff)

const POISON_DOT: PackedScene = preload("res://scenes/debuff/poison_dot.tscn")

@onready var buff_timer = $BuffTimer
@onready var dot_timer = $DotTimer

@export var buff: Buff
@export var buff_id: String
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@export var is_remove_by_layer: bool = false

var player: Node
var body: Node
var num: int
var layer: int = 0
var buff_time: float
var is_stop: bool = false
var hurt_num: int


func _ready():
	player = get_tree().get_first_node_in_group("Player")
	body = get_parent()
	body.enemy_buff_manager.enemy_buff_added.connect(on_buff_added)

func on_buff_added(enemy_buff: Buff, current_buff: Dictionary):
	buff_layer = 1
	buff_time = buff_erase_timer * player.stats.dot_time
	buff_timer.wait_time = buff_time
	if !buff_timer.time_left > 0:
		buff_timer.start()
	if enemy_buff.id != buff_id:
		return
	num = current_buff[buff_id]["quantity"]
	
	if layer >= buff_layer:
		return
	if is_stop == true:
		return
	layer += 1

func poison_hurt():
	
	var anim = PoolManager.get_pool("poison")
	if anim == null or anim.is_idle == 0:
		anim = POISON_DOT.instantiate() as Node2D
		get_tree().get_first_node_in_group("SELayer").add_child(anim)
	
	anim.follow_body(body)
	anim.play_anim()
	body.is_poison_hit = true
	body.hurt_damage = buff_value * player.stats.dot_damage
	body.is_hurt.emit()

func _on_dot_timer_timeout():
	dot_timer.start()
	poison_hurt()

func _on_buff_timer_timeout():
	if is_stop == true:
		return
	if is_remove_by_layer == false:
		for i in layer:
			pass
		layer = 0
	else:
		layer -= 1
	
	if layer <= 0:
		is_stop = true
		buff_time_out.emit(buff)
		queue_free()

func clear_buff():
	if is_stop == true:
		return
	if is_remove_by_layer == false:
		for i in layer:
			pass
		layer = 0
	else:
		layer -= 1
	
	if layer <= 0:
		is_stop = true
		buff_time_out.emit(buff)
		queue_free()
