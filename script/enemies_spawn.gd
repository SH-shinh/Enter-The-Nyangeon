extends Node2D

@export var boss_round: bool = false
@export var boss_position: Vector2
@export var num_mult: float #敌人生成随时间增加的数量
@export var round_mult: float #敌人生成随回合增加的数量
@export var hp_mult: float = 1
@export var damage_mult: float = 1
@export var enemy: Array[EnemyCard] #敌人生成的种类
@export var enemy_spawn_num: Array[int] #每种敌人对应的生成数量
@export var enemy_spawn_time: Array[float] #每种敌人对应的生成cd
@onready var enemy_spawn_cd_time = $EnemySpawnCDTime
@onready var enemy_spawn_anim = preload("res://script/spawn_anim.tscn")

var enemy_spawn_time_copy: Array = []
var time_mult: float
var tilemap: Node
var player: Node
var can_spawn: bool = true
var round_timer: Node
var mode_mult: float = 1
var endless_hp: float = 1
var endless_boss_hp: float = 1
var endless_damage: float = 1
var max_round: float = 20

func _ready():
	tilemap = get_tree().get_first_node_in_group("Map")
	player = get_tree().get_first_node_in_group("Player")
	round_timer = get_tree().get_first_node_in_group("RoundTime")
	enemy_spawn_time_copy = enemy_spawn_time.duplicate()
	update_cd()
	GameEvents.spawn_start.connect(spawn_start)
	GameEvents.boss_round_start.connect(boss_spawn)
	GameEvents.spawn_restart.connect(spawn_restart)
	GameEvents.spawn_stop.connect(spawn_stop)
	GameEvents.spawn_end.connect(spawn_end)

func update_cd():
	for i in enemy_spawn_time_copy.size():
		enemy_spawn_time_copy[i] *= mode_mult

func get_level():
	round_mult *= round_count(PlayerData.level_num, min(3.5, PlayerData.now_round/(max_round * 0.5)) )
	if PlayerData.game_mode.has("hujiu") and boss_round == true:
		hp_mult *= round_count(min(PlayerData.level_hp, 3), (PlayerData.now_round/(max_round * 0.5)) )
	else:
		hp_mult *= round_count(PlayerData.level_hp, (PlayerData.now_round/(max_round * 0.5)) )
	damage_mult *= PlayerData.level_damage

func round_count(x: float, y:float):
	return pow(x, y)

func _physics_process(_delta):
	time_mult = 1 - (round_timer.round_timer.time_left / round_timer.round_timer.wait_time)

func spawn_start():
	get_level()
	enemy_spawn_cd_time.start()

func spawn_restart():
	can_spawn = true

func spawn_stop():
	can_spawn = false

func spawn_end():
	queue_free()

func boss_spawn():
	get_level()
	
	for i in enemy.size():
		var enemy_temp = enemy[i]
		
		
		var spawn_anim = PoolManager.get_pool("spawn_anim")
		if spawn_anim == null or spawn_anim.is_idle == 0:
			spawn_anim = enemy_spawn_anim.instantiate()
			get_tree().get_first_node_in_group("EnemiesRoot").add_child(spawn_anim)
		
		spawn_anim.position = boss_position
		spawn_anim.hp_mult = hp_mult * endless_boss_hp
		spawn_anim.damage_mult = damage_mult * endless_damage
		spawn_anim.is_boss = true
		spawn_anim.active_state()
		spawn_anim.enemy_spawn_anim(enemy_temp)
		GameEvents.emit_enemy_spawn()
		enemy_spawn_time_copy[i] = enemy_spawn_time[i]

func enemy_spawn():
	var ran = RandomNumberGenerator.new()
	var cells: Array = tilemap.get_used_cells(0)
	var cell_count: int = cells.size()
	for i in enemy.size():
		if enemy_spawn_time_copy[i] <= 0:
			for n in floor(enemy_spawn_num[i] + (time_mult * time_mult * num_mult)) * round_mult:
				var rand_position_num = ran.randi_range(0, cell_count) - 1
				var rand_position = tilemap.map_to_local(cells[rand_position_num])
				
				var enemy_temp = enemy[i]
				
				if can_spawn == false:
					return
				
				while rand_position.distance_to(player.position) < 170:
					rand_position_num = ran.randi_range(0, cell_count) - 1
					rand_position = tilemap.map_to_local(cells[rand_position_num])
				
				var spawn_anim = PoolManager.get_pool("spawn_anim")
				if spawn_anim == null or spawn_anim.is_idle == 0:
					spawn_anim = enemy_spawn_anim.instantiate()
					get_tree().get_first_node_in_group("EnemiesRoot").add_child(spawn_anim)
				
				spawn_anim.position = rand_position
				spawn_anim.hp_mult = hp_mult * endless_hp
				spawn_anim.damage_mult = damage_mult * endless_damage
				spawn_anim.active_state()
				spawn_anim.enemy_spawn_anim(enemy_temp)
				GameEvents.emit_enemy_spawn()
			enemy_spawn_time_copy[i] = enemy_spawn_time[i] * mode_mult

func _on_enemy_spawn_cd_time_timeout():
	if can_spawn == false:
		return
	enemy_spawn()
	for i in enemy_spawn_time.size():
		enemy_spawn_time_copy[i] -= 1
