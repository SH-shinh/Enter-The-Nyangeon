extends Node2D

signal is_end

@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@onready var timer = $Timer
@onready var area_2d = $Area2D

var floating_text_scene: PackedScene = preload("res://ui/floating_text.tscn")

var value: Array

var add_end: bool = true

var enemy_group: Array[Node]

func reset():
	if add_end == false:
		return
	else:
		add_end = false
	if !enemy_group.is_empty():
		enemy_group.clear()
	area_2d.set_deferred("monitoring" , true)
	area_2d.set_deferred("monitorable" , true)
	timer.start()


func fire_dot_add():
	if !enemy_group.is_empty():
		value = [buff_layer, buff_value, buff_erase_timer]
		for i in range(enemy_group.size() - 1, -1, -1):
			var enemy = enemy_group[i]
			if enemy == null or not is_instance_valid(enemy):
				enemy_group.remove_at(i)
				continue
			enemy.enemy_buff_manager.apply_buff(enemy_buff, value)
		
		var floating_text = PoolManager.get_pool("floating_text")
		if floating_text == null or floating_text.is_idle == 0:
			floating_text = floating_text_scene.instantiate() as Node2D
			get_tree().get_first_node_in_group("ForegroundLayer").add_child(floating_text)
		
		floating_text.set_style(Color(1, 0.367, 0.178), 16)
		floating_text.global_position = global_position + (Vector2.UP * randf_range(5,15)) + (Vector2.RIGHT * randf_range(-15,15))
		floating_text.start(tr("dot_spread") + "!")


func _on_area_2d_body_entered(body):
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Enemy") and !enemy_group.has(body):
		enemy_group.push_back(body)


func _on_area_2d_body_exited(body):
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Enemy") and enemy_group.has(body):
		enemy_group.remove_at(enemy_group.find(body))


func _on_timer_timeout():
	add_end = true
	fire_dot_add()
	area_2d.monitoring = false
	area_2d.monitorable = false
