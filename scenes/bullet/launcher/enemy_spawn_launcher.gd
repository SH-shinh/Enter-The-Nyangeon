extends Node2D

@export var center := Vector2(0, 0)  # 圆心坐标
@export var radius := 70.0              # 半径
@export var point_count := 8             # 想要取的点数

@export var hp_mult: float = 1
@export var damage_mult: float = 1
@export var enemy: Array[EnemyCard] #敌人生成的种类
@export var enemy_spawn_num: Array[int] #每种敌人对应的生成数量

@onready var enemy_spawn_anim = preload("res://script/spawn_anim.tscn")

var can_spawn: bool = true

var spawn_index: int = 0
var endless_hp: float = 1
var endless_boss_hp: float = 1
var endless_damage: float = 1
var max_round: float = 20

func _ready() -> void:
	GameEvents.spawn_restart.connect(spawn_restart)
	GameEvents.spawn_stop.connect(spawn_stop)

# 获取圆边上点的坐标数组
func get_points_on_circle(center_local: Vector2, radius_local: float, count: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if count <= 0:
		return points
	
	var angle_step = 2 * PI / count  # 每个点之间的角度间隔
	
	for i in range(count):
		# 当前点的角度，这里从右侧(0度)开始逆时针旋转
		var angle = i * angle_step
		# 计算坐标
		var x = center_local.x + radius_local * cos(angle)
		var y = center_local.y + radius_local * sin(angle)
		points.append(Vector2(x, y))
	
	return points

func spawn_restart():
	can_spawn = true

func spawn_stop():
	can_spawn = false

func spawn_enemy(index: int) -> void:
	if enemy.size() - 1 >= index:
		var quantity: int = enemy_spawn_num[index]
		point_count = quantity
		center = self.global_position
		var spawn_points: Array[Vector2] = get_points_on_circle(center, radius, point_count)
		for i in spawn_points.size():
			if can_spawn == false:
				return
			var enemy_temp = enemy[index]
			var spawn_anim = PoolManager.get_pool("spawn_anim")
			if spawn_anim == null or spawn_anim.is_idle == 0:
				spawn_anim = enemy_spawn_anim.instantiate()
				get_tree().get_first_node_in_group("EnemiesRoot").add_child(spawn_anim)
			
			spawn_anim.position = spawn_points[i]
			spawn_anim.hp_mult = hp_mult
			spawn_anim.damage_mult = damage_mult
			spawn_anim.coin_mult = 0
			spawn_anim.active_state()
			spawn_anim.enemy_spawn_anim(enemy_temp)
			GameEvents.emit_enemy_spawn()
