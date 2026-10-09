extends Node2D

@export var enemy_pool: Array[EnemyCard]
@export var enemy_quantity: Array[int]
@export var enemy_spawn_time: Array[float] #每种敌人对应的生成cd
@export var enemy_spawn_path: Array[PackedScene]
@export var points: Array[Vector2] #已弃用：生成点现在从 enemy_spawn_path 自动取

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
			var path_probe: Node = null
			if enemy_spawn_path[i] != null:
				path_probe = enemy_spawn_path[i].instantiate()
			for n in enemy_quantity[i]:
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
				spawn_anim.global_position = _spawn_position(path_probe, n, enemy_quantity[i])
				spawn_anim.active_state()
				spawn_anim.enemy_spawn_anim(enemy_temp)
				GameEvents.emit_enemy_spawn()
			if path_probe != null:
				path_probe.free()
			enemy_spawn_time_copy[i] = enemy_spawn_time[i] * spawn_round.mode_mult

func _spawn_position(path_probe: Node, n: int, count: int) -> Vector2:
	if path_probe != null and path_probe.has_method("get_spawn_point"):
		var p: Vector2 = path_probe.call("get_spawn_point", float(n) / float(count))
		return p
	if n < points.size():
		return points[n] + Vector2(704, 448)
	return Vector2(704, 448)
