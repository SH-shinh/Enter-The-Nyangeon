extends Node

var pool:Dictionary = {}

var num: int = 0
var enemies_group: Array[Node]
var enemies_size: int = 0

var buff_box: Node

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
	
	var has_pool = pool.has(body_name)
	
	if !has_pool:
		pool[body_name] = {
			"resource": body_name,
			"body": [body],
			"index": 0
		}
	else:
		pool[body_name]["body"].push_back(body)

func get_buff_pool():
	var group = buff_box.get_children()
	if !group.is_empty():
		return group[0]
	else:
		return null

func sort_pool(body_name: String):
	pass

func get_pool(body_name: String):
	if pool.has(body_name):
		var body = pool[body_name]["body"]
		if !body.is_empty():
			
			var max_value = body.size()
			var pool_index = pool[body_name]["index"]
			
			if max_value > 150 and body_name == "player_bullet" :
				body[pool_index].idle_state()
			elif max_value > 100 and body_name == "player_sniper_bullet" :
				body[pool_index].idle_state()
			elif max_value > 60 and body_name == "shiro_missile" :
				body[pool_index].idle_state()
			elif max_value > 30 and body_name == "explosion_particles" :
				body[pool_index].idle_state()
			elif max_value > 30 and body_name == "explosion_smoke_particles" :
				body[pool_index].idle_state()
			elif max_value > 150 and body_name == "normal_bullet" :
				body[pool_index].idle_state()
			elif max_value > 100 and body_name == "player_explosion" :
				body[pool_index].idle_state()
			elif max_value > 15 and body_name == "small_explosion" :
				body[pool_index].idle_state()
			elif max_value > 20 and body_name == "big_explosion" :
				body[pool_index].idle_state()
			elif max_value > 200 and body_name == "enemy_bullet_1" :
				body[pool_index].idle_state()
			elif max_value > 40 and body_name == "enemy_bullet_2" :
				body[pool_index].idle_state()
			elif max_value > 20 and body_name == "enemy_missile_1" :
				body[pool_index].idle_state()
			elif max_value > 20 and body_name == "enemy_explosion" :
				body[pool_index].idle_state()
			elif max_value > 30 and body_name == "bullet_smoke_1" :
				body[pool_index].idle_state()
			elif max_value > 30 and body_name == "bullet_smoke_2" :
				body[pool_index].idle_state()
			elif max_value > 100 and body_name == "floating_text" :
				body[pool_index].idle_state()
			elif max_value > 30 and body_name == "fire" :
				body[pool_index].idle_state()
			elif max_value > 30 and body_name == "poison" :
				body[pool_index].idle_state()
			elif max_value > 5 and body_name == "player_flash" :
				body[pool_index].idle_state()
			elif max_value > 10 and body_name == "enemy_flash_1" :
				body[pool_index].idle_state()
			elif max_value > 5 and body_name == "summoned_flash_1" :
				body[pool_index].idle_state()
			elif max_value > 20 and body_name == "floor_paint" :
				body[pool_index].idle_state()
			elif max_value > 100 and body_name == "enemy_fire_field" :
				body[pool_index].idle_state()
			elif max_value > 60 and body_name == "support_bullet" :
				body[pool_index].idle_state()
			elif max_value > 10 and body_name == "hit_flash" :
				body[pool_index].idle_state()
			elif max_value > 10 and body_name == "hit_flash_2" :
				body[pool_index].idle_state()
			
			if body[pool_index].is_idle == 1:
				pool[body_name]["index"] = wrapi(pool_index + 1, 0, max_value)
			
			return body[pool_index]
	else:
		return null

func add_text(text: String,text_position: Vector2, text_color: Color, text_size: int):
	
	var floating_text = PoolManager.get_pool("floating_text")
	if floating_text == null or floating_text.is_idle == 0:
		floating_text = floating_text_scene.instantiate() as Node2D
		get_tree().get_first_node_in_group("ForegroundLayer").add_child(floating_text)
	
	floating_text.label.set("theme_override_colors/font_color", text_color)
	floating_text.label.set("theme_override_font_sizes/font_size", text_size)
	floating_text.global_position = text_position + (Vector2.UP * randf_range(15,25)) + (Vector2.RIGHT * randf_range(-15,15))
	floating_text.start(text)
