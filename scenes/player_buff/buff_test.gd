extends Node2D

signal buff_time_out(player_buff: Node)

@onready var buff_timer = $BuffTimer

@export var buff_id: String
@export var buff_layer: int

var num
var layer = 0

func _ready():
	GameEvents.player_buff_added.connect(on_buff_added)

func on_buff_added(player_buff: Buff, current_buff: Dictionary):
	if player_buff.id != buff_id:
		return
	buff_timer.start()
	num = current_buff[buff_id]["quantity"]
	
	if layer >= buff_layer:
		return
	PlayerData.bullet_damage_add += 10
	layer += 1
	PlayerData.update_player_ability()


func _on_buff_timer_timeout():
	#PlayerData.bullet_damage_add -= 10 * layer
	PlayerData.bullet_damage_add -= 10
	layer -= 1
	PlayerData.update_player_ability()
	if layer <= 0:
		buff_time_out.emit(self)
		queue_free()
