extends Node

var pool:Dictionary = {}

var num: int = 0
var enemies_group: Array[Node]
var enemies_size: int = 0

var buff_box: Node

const IDLE_LIMITS := {
	"player_bullet": 150,
	"player_sniper_bullet": 100,
	"shiro_missile": 60,
	"explosion_particles": 30,
	"explosion_smoke_particles": 30,
	"normal_bullet": 150,
	"player_explosion": 100,
	"small_explosion": 15,
	"big_explosion": 20,
	"enemy_bullet_1": 200,
	"enemy_bullet_2": 40,
	"enemy_missile_1": 20,
	"enemy_explosion": 20,
	"bullet_smoke_1": 30,
	"bullet_smoke_2": 30,
	"floating_text": 100,
	"fire": 30,
	"poison": 30,
	"chill": 30,
	"player_flash": 5,
	"enemy_flash_1": 10,
	"summoned_flash_1": 5,
	"floor_paint": 20,
	"enemy_fire_field": 100,
	"support_bullet": 60,
	"hit_flash": 10,
	"hit_flash_2": 10,
}

@onready var floating_text_scene: PackedScene = preload("res://ui/floating_text.tscn")

func get_buff_box():
	buff_box = get_tree().get_first_node_in_group("BuffBox")

func lear_buff_box():
	if buff_box != null:
		var group = buff_box.get_children()
		if !group.is_empty():
			for i in buff_box.get_children():
				i.queue_free()
			erase_pool("buff_box")

func erase_pool(body_name: String):
	if pool.has(body_name):
		pool.erase(body_name)

func clear_pool():
	pool.clear()

func check_enemies():
	enemies_size = enemies_group.size()
	if enemies_size > 80:
		GameEvents.emit_spawn_stop()
	else:
		GameEvents.emit_spawn_restart()

func add_pool(body_name: String, body: Node):
	var entry = pool.get(body_name)
	if entry == null:
		pool[body_name] = {
			"resource": body_name,
			"body": [body],
			"index": 0,
			"limit": IDLE_LIMITS.get(body_name, -1),
			"set": {body: true}
		}
	elif entry["set"].has(body):
		return
	else:
		entry["body"].push_back(body)
		entry["set"][body] = true

func get_buff_pool():
	if buff_box == null or not is_instance_valid(buff_box):
		return null
	for child in buff_box.get_children():
		if child.get("is_idle") == 1:
			return child
	return null

func sort_pool(_body_name: String):
	pass

func get_pool(body_name: String):
	var entry = pool.get(body_name)
	if entry == null:
		return null
	var body = entry["body"]
	if body.is_empty():
		return null
	
	var max_value = body.size()
	var pool_index = entry["index"]
	
	var limit: int = entry["limit"]
	if limit >= 0 and max_value > limit:
		body[pool_index].idle_state()
	
	if body[pool_index].is_idle != 1:
		var scan_max: int = mini(max_value, 64)
		for s in range(1, scan_max):
			var scan_index: int = wrapi(pool_index + s, 0, max_value)
			if body[scan_index].is_idle == 1:
				pool_index = scan_index
				break
	
	if body[pool_index].is_idle == 1:
		entry["index"] = wrapi(pool_index + 1, 0, max_value)
	
	return body[pool_index]

func get_pool_idle(body_name: String):
	var entry = pool.get(body_name)
	if entry == null:
		return null
	var body = entry["body"]
	var max_value = body.size()
	if max_value == 0:
		return null
	var pool_index = entry["index"]
	if body[pool_index].is_idle != 1:
		var scan_max: int = mini(max_value, 32)
		for s in range(1, scan_max):
			var scan_index: int = wrapi(pool_index + s, 0, max_value)
			if body[scan_index].is_idle == 1:
				pool_index = scan_index
				break
	if body[pool_index].is_idle != 1:
		return null
	entry["index"] = wrapi(pool_index + 1, 0, max_value)
	return body[pool_index]

func add_text(text: String,text_position: Vector2, text_color: Color, text_size: int):
	
	var floating_text = PoolManager.get_pool("floating_text")
	if floating_text == null or floating_text.is_idle == 0:
		floating_text = floating_text_scene.instantiate() as Node2D
		get_tree().get_first_node_in_group("ForegroundLayer").add_child(floating_text)
	
	floating_text.set_style(text_color, text_size)
	floating_text.global_position = text_position + (Vector2.UP * randf_range(15,25)) + (Vector2.RIGHT * randf_range(-15,15))
	floating_text.start(text)
