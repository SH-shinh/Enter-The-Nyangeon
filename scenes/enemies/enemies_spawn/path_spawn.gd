extends Node2D

@export var enemy_pool: Array[EnemyCard]
@export var enemy_quantity: Array[int]
@export var enemy_spawn_time: Array[float] #每种敌人对应的生成cd
@export var enemy_spawn_path: Array[PackedScene]
@export var points: Array[Vector2]

@onready var enemy_spawn_anim = preload("res://script/spawn_anim.tscn")

var spawn_round: Node
var can_spawn: bool = true
var enemy_spawn_time_copy: Array = []

func _ready():
	spawn_round = get_parent()
	enemy_spawn_time_copy = enemy_spawn_time.duplicate()
	update_cd()
	GameEvents.global_time_count.connect(time_count)
	GameEvents.spawn_start.connect(spawn_start)
	GameEvents.spawn_stop.connect(spawn_stop)

func update_cd():
	for i in enemy_spawn_time_copy.size():
		enemy_spawn_time_copy[i] *= spawn_round.mode_mult

func spawn_start():
	can_spawn = true

func spawn_stop():
	can_spawn = false

func time_count():
	if can_spawn == false:
		return
	enemy_spawn()
	for i in enemy_spawn_time.size():
		enemy_spawn_time_copy[i] -= 1

func enemy_spawn():
	for i in enemy_pool.size():
		if enemy_spawn_time_copy[i] == 0:
			for n in enemy_quantity[i]:
				var path_ins = enemy_spawn_path[i].instantiate()
				var enemy_temp = enemy_pool[i]
				var spawn_anim = PoolManager.get_pool("spawn_anim")
				if spawn_anim == null or spawn_anim.is_idle == 0:
					spawn_anim = enemy_spawn_anim.instantiate()
					get_tree().get_first_node_in_group("EnemiesRoot").add_child(spawn_anim)
				spawn_anim.path = enemy_spawn_path[i]
				spawn_anim.path_value = float(n) / float(enemy_quantity[i])
				spawn_anim.has_path = true
				spawn_anim.hp_mult = spawn_round.hp_mult * spawn_round.endless_hp
				spawn_anim.damage_mult = spawn_round.damage_mult * spawn_round.endless_damage
				spawn_anim.global_position = points[n] + Vector2(704,448)
				spawn_anim.active_state()
				spawn_anim.enemy_spawn_anim(enemy_temp)
				GameEvents.emit_enemy_spawn()
			enemy_spawn_time_copy[i] = enemy_spawn_time[i] * spawn_round.mode_mult
