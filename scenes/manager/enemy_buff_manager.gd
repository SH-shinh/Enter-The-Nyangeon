extends Node

const FIRE_DOT: PackedScene = preload("res://scenes/debuff/fire_dot.tscn")
const POISON_DOT: PackedScene = preload("res://scenes/debuff/poison_dot.tscn")

signal enemy_buff_added(enemy_buff: Buff, current_buff: Dictionary)

@export var buff_poll: Array[Buff]
@export var buff_card: PackedScene

var current_buff = {}
var body: Node

var player: Node

func _ready():
	body = get_parent()
	GameEvents.global_time_count.connect(buff_count)
	GameEvents.get_player.connect(get_player)
	get_player()

func get_player():
	player = get_tree().get_first_node_in_group("Player")

func add_buff_card(enemy_buff: Buff, buff_node: Node):
	var buff_card_instance = buff_card.instantiate()
	body.buff_box.add_child(buff_card_instance)
	buff_card_instance.set_buff_card(enemy_buff)
	buff_card_instance.get_player_buff(buff_node)

func emit_enemy_buff_added(enemy_buff: Buff, current_buff: Dictionary):
	enemy_buff_added.emit(enemy_buff, current_buff)

func buff_count():
	var buff_group = current_buff.values()
	for i in buff_group.size():
		var id = buff_group[i]["resource"].id
		current_buff[id]["now_time"] += 1
		if current_buff[id]["buff_card"] != null:
			current_buff[id]["buff_card"].now_time = current_buff[id]["now_time"]
			current_buff[id]["buff_card"].erase_time = current_buff[id]["erase_time"]
		
		if current_buff[id]["resource"].id == "fire_dot":
			current_buff[id]["now_dot_time"] += 1
			if current_buff[id]["now_dot_time"] >= current_buff[id]["dot_time"]:
				current_buff[id]["now_dot_time"] = 0
				var anim = PoolManager.get_pool("fire")
				if anim == null or anim.is_idle == 0:
					anim = FIRE_DOT.instantiate() as Node2D
					get_tree().get_first_node_in_group("SELayer").add_child(anim)
				
				anim.follow_body(body)
				anim.play_anim()
				body.is_fire_hit = true
				body.hurt_damage = max(1, 8 * player.stats.dot_damage * player.stats.global_damage * current_buff[id]["layer"])
				body.is_hurt.emit()
		
		if current_buff[id]["resource"].id == "poison_dot":
			current_buff[id]["now_dot_time"] += 1
			if current_buff[id]["now_dot_time"] > current_buff[id]["dot_time"]:
				current_buff[id]["now_dot_time"] = 0
				var anim = PoolManager.get_pool("poison")
				if anim == null or anim.is_idle == 0:
					anim = POISON_DOT.instantiate() as Node2D
					get_tree().get_first_node_in_group("SELayer").add_child(anim)
				
				anim.follow_body(body)
				anim.play_anim()
				body.is_poison_hit = true
				body.hurt_damage = max(1, current_buff[id]["value"] * player.stats.dot_damage)
				body.is_hurt.emit()
		
		if current_buff[id]["now_time"] > current_buff[id]["erase_time"]:
			current_buff[id]["now_time"] = 0
			if current_buff[id]["resource"].remove_by_layer == false:
				if current_buff[id]["stop"] == false:
					current_buff[id]["stop"] = true
					if current_buff[id]["buff_card"] != null:
						current_buff[id]["buff_card"].layer = current_buff[id]["layer"]
					if current_buff[id]["resource"].ability != "":
						var first = body.stats.get(current_buff[id]["resource"].ability)
						body.stats.set( current_buff[id]["resource"].ability , first - current_buff[id]["value"] * current_buff[id]["layer"] )
						body.stats.update_body_ability()
					if current_buff[id]["buff_card"] != null:
						current_buff[id]["buff_card"].clear_card()
					current_buff.erase(id)
			else:
				if current_buff[id]["stop"] == false:
					current_buff[id]["layer"] -= 1
					if current_buff[id]["buff_card"] != null:
						current_buff[id]["buff_card"].layer = current_buff[id]["layer"]
					if current_buff[id]["resource"].ability != "":
						var first = body.stats.get(current_buff[id]["resource"].ability)
						body.stats.set( current_buff[id]["resource"].ability , first - current_buff[id]["value"] )
						body.stats.update_body_ability()
					if current_buff[id]["layer"] <= 0:
						current_buff[id]["stop"] = true
						if current_buff[id]["buff_card"] != null:
							current_buff[id]["buff_card"].clear_card()
						current_buff.erase(id)
			
			if current_buff.has(id):
				if current_buff[id]["resource"].id == "fire_dot":
					current_buff[id]["dot_time"] = 20 / float(current_buff[id]["layer"])
					current_buff[id]["erase_time"] = 100 / float(current_buff[id]["layer"])
					
			


func apply_buff(enemy_buff: Buff, value: Array):
	var has_buff = current_buff.has(enemy_buff.id)
	if !has_buff:
		
		if body.get("buff_box") != null:
			var buff_card_instance = PoolManager.get_buff_pool()
			if buff_card_instance == null:
				buff_card_instance = buff_card.instantiate()
				body.buff_box.add_child(buff_card_instance)
			else:
					buff_card_instance.reparent(body.buff_box)
			buff_card_instance.set_buff_card(enemy_buff)
			buff_card_instance.active_state()
		
			current_buff[enemy_buff.id] = {
				"resource": enemy_buff,
				"layer": 1,
				"max_layer": value[0],
				"value": value[1],
				"erase_time": value[2] * 10,
				"now_time": 0,
				"dot_time": 0,
				"now_dot_time": 0,
				"buff_card": buff_card_instance,
				"stop": false 
			}
		
		else:
			current_buff[enemy_buff.id] = {
				"resource": enemy_buff,
				"layer": 1,
				"max_layer": value[0],
				"value": value[1],
				"erase_time": value[2] * 10,
				"now_time": 0,
				"dot_time": 0,
				"now_dot_time": 0,
				"buff_card": null,
				"stop": false 
			}
		
		
		if current_buff[enemy_buff.id]["resource"].id == "fire_dot" or current_buff[enemy_buff.id]["resource"].id == "poison_dot":
			current_buff[enemy_buff.id]["erase_time"] *= player.stats.dot_time
		
		if current_buff[enemy_buff.id]["resource"].id == "poison_dot":
			current_buff[enemy_buff.id]["dot_time"] = 3
		
		
		if current_buff[enemy_buff.id]["buff_card"] != null:
			current_buff[enemy_buff.id]["buff_card"].now_time = current_buff[enemy_buff.id]["now_time"]
			current_buff[enemy_buff.id]["buff_card"].erase_time = current_buff[enemy_buff.id]["erase_time"]
			current_buff[enemy_buff.id]["buff_card"].layer = current_buff[enemy_buff.id]["layer"]
		
	else:
		
		if current_buff[enemy_buff.id]["stop"] == true:
			return
		
		current_buff[enemy_buff.id]["now_time"] = 0
		if current_buff[enemy_buff.id]["layer"] < current_buff[enemy_buff.id]["max_layer"]:
			current_buff[enemy_buff.id]["layer"] += 1
			if current_buff[enemy_buff.id]["buff_card"] != null:
				current_buff[enemy_buff.id]["buff_card"].layer = current_buff[enemy_buff.id]["layer"]
		else:
			return
	
	if current_buff[enemy_buff.id]["resource"].id == "fire_dot":
		current_buff[enemy_buff.id]["max_layer"] = player.stats.fire_dot_layer
		current_buff[enemy_buff.id]["dot_time"] = 20 / float(current_buff[enemy_buff.id]["layer"])
		current_buff[enemy_buff.id]["erase_time"] = 100 / float(current_buff[enemy_buff.id]["layer"])
		if current_buff[enemy_buff.id]["buff_card"] != null:
			current_buff[enemy_buff.id]["buff_card"].erase_time = current_buff[enemy_buff.id]["erase_time"]
	
	
	
	if enemy_buff.ability != "":
		var first = body.stats.get(current_buff[enemy_buff.id]["resource"].ability)
		body.stats.set( current_buff[enemy_buff.id]["resource"].ability , first + current_buff[enemy_buff.id]["value"] )
		body.stats.update_body_ability()


func clear_all_buff():
	if current_buff.is_empty():
		return
	var buff_group = current_buff.values()
	for i in buff_group.size():
		if buff_group[i] != null:
			var id = buff_group[i]["resource"].id
			if current_buff[id]["stop"] == false:
				current_buff[id]["stop"] = true
				if current_buff[id]["resource"].ability != "":
					var first = body.stats.get(current_buff[id]["resource"].ability)
					body.stats.set( current_buff[id]["resource"].ability , first - current_buff[id]["value"] * current_buff[id]["layer"] )
					body.stats.update_body_ability()
				if current_buff[id]["buff_card"] != null:
					current_buff[id]["buff_card"].clear_card()
				current_buff.erase(id)


func remove_buff(enemy_buff: Buff):
	
	if current_buff.has(enemy_buff):
		
		if current_buff[enemy_buff.id]["stop"] == false:
			current_buff[enemy_buff.id]["stop"] = true
			if current_buff[enemy_buff.id]["resource"].ability != null:
				var first = body.stats.get(current_buff[enemy_buff.id]["resource"].ability)
				body.stats.set( current_buff[enemy_buff.id]["resource"].ability , first - current_buff[enemy_buff.id]["value"] * current_buff[enemy_buff.id]["layer"] )
				body.stats.update_body_ability()
			if current_buff[enemy_buff.id]["buff_card"] != null:
				current_buff[enemy_buff.id]["buff_card"].clear_card()
			current_buff.erase(enemy_buff.id)
