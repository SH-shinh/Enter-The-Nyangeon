extends Node2D

@export var stats: EnemyStats
@export var tower_1: Node
@export var tower_2: Node
@export var tower_3: Node

@onready var camera_marker: Marker2D = $boss_enter/CameraMarker
@onready var coins: PackedScene = preload("res://scenes/item/coin_box.tscn")
@onready var pyroxenes: PackedScene = preload("res://scenes/item/pyroxenes.tscn")
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var tower_group: Array[Node]
var body_part: Array[Node]

var shoot_cd: int = 0
var shoot_time: int = 0

var shoot_time_max = 60
var shoot_cd_max = 25

var attack_type: int = 1

func active_state():
	await get_tree().create_timer(0.1).timeout
	update_tower()
	count_max_hp()
	boss_enter_anim()
	stats.hp_changed.connect(count_hp)
	GameEvents.global_time_count.connect(time_count)

func count_hp():
	if stats.hp <= stats.max_hp * 0.5:
		attack_type = 2
	else:
		attack_type = 1

func time_count():
	if shoot_time > 0:
		shoot_time -= 1
		if shoot_time <= 0:
			shoot_cd = shoot_cd_max
			stop_shoot()
	
	if shoot_cd > 0:
		shoot_cd -= 1
		if shoot_cd <= 0:
			attack_state(attack_type)

func stop_shoot():
	for i in tower_group:
		i.can_shoot = false

func attack_state(type: int):
	shoot_time = shoot_time_max
	match attack_type:
		1:
			attack_type_1()
		2:
			attack_type_2()

func attack_type_1():
	var rand_group: Array
	for i in tower_group.size() - 1:
		if tower_group[i].is_idle != 1:
			rand_group.append(tower_group[i])
	if !rand_group.is_empty():
		var n = randi_range(0, rand_group.size() - 1)
		rand_group[n].can_shoot = true
	tower_3.can_shoot = true

func attack_type_2():
	for i in tower_group:
		i.can_shoot = true

func update_tower():
	tower_group = [tower_1, tower_2, tower_3]
	for i in tower_group:
		i.stats.hp_changed.connect(count_now_hp)
		i.stats.max_hp_mult = stats.max_hp_mult
		i.stats.Enemy_damage_mult = stats.Enemy_damage_mult
		i.stats.Enemy_bullet_damage_mult = stats.Enemy_bullet_damage_mult
		i.stats.update_body_ability()
		i.active_state()

func boss_dead(tower: ErosionTower):
	if stats.hp <= 0:
		GameEvents.emit_boss_round_end()
		tower.animation_player_1.process_mode = Node.PROCESS_MODE_ALWAYS
		tower.animation_player_2.process_mode = Node.PROCESS_MODE_ALWAYS
		tower.animation_player_3.process_mode = Node.PROCESS_MODE_ALWAYS
		animation_player.play("death_anim")
		camera_marker.position = tower.position + Vector2(0, -64)
		GameEvents.emit_camera_move(camera_marker, true)
		GameEvents.emit_ui_visible(false)
		get_tree().paused = true
		await animation_player.animation_finished
		GameEvents.emit_camera_reset()
		GameEvents.emit_ui_visible(true)
		get_tree().paused = false
		GameEvents.emit_enemy_dead_position(self.global_position)
		self.visible = false
		for i in tower_group:
			i.idle_state.call_deferred()

func boss_enter_anim():
	for i in tower_group:
		i.tower_dead.connect(boss_dead)
		i.animation_player_3.process_mode = Node.PROCESS_MODE_ALWAYS
		i.animation_player_3.play("enter_anim")
	GameEvents.emit_camera_move(camera_marker, true)
	GameEvents.emit_ui_visible(false)
	self.visible = true
	get_tree().paused = true
	await tower_1.animation_player_3.animation_finished
	for i in tower_group:
		i.animation_player_3.process_mode = Node.PROCESS_MODE_INHERIT
	GameEvents.emit_camera_reset()
	GameEvents.emit_ui_visible(true)
	get_tree().paused = false
	attack_state(attack_type)

func count_now_hp():
	stats.hp = tower_1.stats.hp + tower_2.stats.hp + tower_3.stats.hp

func count_max_hp():
	
	var max_value = tower_1.stats.base_max_hp + tower_2.stats.base_max_hp + tower_3.stats.base_max_hp
	stats.base_max_hp = max_value
	stats.update_body_ability()
	count_now_hp()

func _coin_drops():
	var coin_box = coins.instantiate()
	var p_box = pyroxenes.instantiate()
	coin_box.global_position = self.global_position
	coin_box.coin_count = stats.Enemy_coin
	coin_box.coin_quantity = 100
	p_box.global_position = self.global_position
	get_tree().get_first_node_in_group("CoinRoot").add_child(coin_box)
	get_tree().get_first_node_in_group("CoinRoot").add_child(p_box)
	await animation_player.animation_finished
	coin_box.add_coin()
	PoolManager.erase_pool("erosion_tower")
	queue_free()

func enemy_fever_time():
	shoot_time_max = 55
	shoot_cd_max = 15
