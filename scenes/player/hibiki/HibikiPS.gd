extends PlayerPS

@export var player_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@export var player_buff_2: Buff
@export var buff_layer_2: int
@export var buff_value_2: float
@export var buff_erase_timer_2: float

@onready var timer = $Timer
@onready var bullet_buff_timer = $BulletBuffTimer

@onready var target_cross = preload("res://scenes/crosshair/target_crosshiar.tscn")
@onready var bullet_launcher = preload("res://scenes/update_item/player_bullet_launcher.tscn")

var on_ready: bool = false

var value: Array
var value_2: Array

var explosion_num: int = 3

var center_p: Vector2 = Vector2(704, 448)

var target_group: Dictionary

var target_num: int = 1
var target_id: Array = []
var cross_group: Array = []
var launcher: Node

func _ready():
	value = [buff_layer, buff_value, buff_erase_timer]
	PlayerData.set_player.connect(set_playerdata)
	GameEvents.player_bullet_explosion.connect(explosion_count)
	GameEvents.player_ps_upgrade.connect(ps_upgrade)

func set_playerdata():
	on_ready = true
	
	PlayerData.max_ammo_value = 1
	
	var ins = bullet_launcher.instantiate()
	ins.shoot_at_once = false
	ins.end_free = false
	get_tree().get_first_node_in_group("EquipLayer").add_child(ins)
	launcher = ins
	
	add_group()
	
	timer.start()

func add_group():
	
	var cross = target_cross.instantiate()
	get_tree().get_first_node_in_group("ForegroundLayer").add_child(cross)
	cross_group.push_back(cross)
	
	if target_group.has(str("target" + str(target_num))):
		target_num += 1
	var target_position = rand_position()
	target_group[str("target" + str(target_num))] = {
		"position": target_position,
		"cross": cross,
		"time": 0
	}
	target_group[str("target" + str(target_num))]["cross"].global_position = target_group[str("target" + str(target_num))]["position"]

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		for i in 2:
			add_group()
	elif now_t == 2:
		for i in 3:
			add_group()
		buff_value += 1
		value = [buff_layer, buff_value, buff_erase_timer]
		
	elif now_t == 3:
		explosion_num = 5
		value_2 = [buff_layer_2, buff_value_2, buff_erase_timer_2]

func rand_position():
	var map_center = Vector2(704, 448)
	var rx = 888
	var ry = 440
	var player_pos = player.global_position
	var max_distance = 400.0
	
	var point = generate_point_near_player(map_center, rx, ry, player_pos, max_distance)
	
	return point

func generate_point_near_player(map_center: Vector2, radius_x: int, radius_y: int, player_pos: Vector2, max_distance: float):
	var max_attempts = 1000
	var attempts = 0
	
	while attempts < max_attempts:
		# 随机生成点
		var x = randf_range(map_center.x - radius_x, map_center.x + radius_x)
		var y = randf_range(map_center.y - radius_y, map_center.y + radius_y)
		
		# 检查是否在地图菱形内
		var dx = x - map_center.x
		var dy = y - map_center.y
		var in_diamond = abs(dx) * radius_y + abs(dy) * radius_x <= radius_x * radius_y
		
		# 检查是否在玩家距离内
		var near_player = Vector2(x, y).distance_to(player_pos) <= max_distance
		
		if in_diamond and near_player:
			return Vector2(x, y)
		
		attempts += 1
	
	return player.global_position

func explosion_count(bullet_position: Vector2):
	if !target_group.is_empty():
		for i in target_group.size():
			if target_group[str("target" + str(i + 1))]["position"].distance_to(bullet_position) < 50:
				
				launcher.global_position = target_group[str("target" + str(i + 1))]["position"]
				launcher.rotation = randf_range(0, PI)
				launcher.bullet = player.gun.bullet
				launcher.bullet_count = explosion_num
				launcher.bullet_arc = 360 * ( 1.0 - 1.0/float(explosion_num) )
				launcher.bullet_speed = player.stats.bullet_speed
				launcher.collision_num = player.stats.collision_num
				launcher.shoot_bullet()
				target_group[str("target" + str(i + 1))]["position"] = rand_position()
				target_group[str("target" + str(i + 1))]["cross"].global_position = target_group[str("target" + str(i + 1))]["position"]
				
				if now_t >= 1:
					PlayerData.explosion_range_mult += 0.01

func _physics_process(_delta):
	
	if on_ready == false:
		return
	
	if player.velocity.length() < 50:
		player.player_buff_manager.apply_buff(player_buff, value)
		if now_t > 2 and bullet_buff_timer.is_stopped():
			bullet_buff_timer.start()
			player.player_buff_manager.apply_buff(player_buff_2, value_2)
	else:
		if player.player_buff_manager.current_buff.has(player_buff.id):
			player.player_buff_manager.remove_buff(player_buff)
		if player.player_buff_manager.current_buff.has(player_buff_2.id):
			player.player_buff_manager.remove_buff(player_buff_2)



func _on_timer_timeout():
	if target_group.is_empty():
		return
	for i in target_group.size():
		target_group[str("target" + str(i + 1))]["time"] += 1
		if target_group[str("target" + str(i + 1))]["time"] > 25:
			target_group[str("target" + str(i + 1))]["position"] = rand_position()
			target_group[str("target" + str(i + 1))]["cross"].global_position = target_group[str("target" + str(i + 1))]["position"]
			target_group[str("target" + str(i + 1))]["time"] = 0
