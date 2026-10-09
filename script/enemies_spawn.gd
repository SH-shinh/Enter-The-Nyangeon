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
var round_damage_curve: Curve
var round_hp_curve: Curve
var round_boss_hp_curve: Curve
var hp_growth_curve: Curve
var max_round: float = 20

# 玩家会在换角色时被销毁重建；刷怪点长期存活，取用前统一重新解析（见 PlayerRef）。
func _ensure_player() -> Node:
	player = PlayerRef.ensure(self, player)
	return player

func _ready():
	tilemap = get_tree().get_first_node_in_group("Map")
	player = PlayerRef.resolve(self)
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
	# 联机人数缩放：mod 经 ExtensionHooks 注入附加数量乘数（未注入时保持 1.0，单机零回归）。
	if ExtensionHooks.enemy_spawn_count_scale.is_valid():
		round_mult *= maxf(0.0, float(ExtensionHooks.enemy_spawn_count_scale.call(PlayerData.now_round, max_round)))
	var hp_round_x: float = 0.0 if max_round <= 1.0 else clamp((PlayerData.now_round - 1.0) / (max_round - 1.0), 0.0, 1.0)
	var hp_curve: Curve = round_boss_hp_curve if boss_round else round_hp_curve
	var hp_base: float = hp_curve.sample(hp_round_x) if hp_curve != null else hp_mult
	var hp_growth: float = hp_growth_curve.sample(PlayerData.now_round / max_round) if hp_growth_curve != null else PlayerData.now_round / (max_round * 0.5)
	var hp_lv: float = min(PlayerData.level_hp, 3.0) if (PlayerData.game_mode.has("hujiu") and boss_round) else PlayerData.level_hp
	hp_mult = hp_base * pow(hp_lv, hp_growth) if !PlayerData.on_endless else hp_base * pow(max(1, hp_lv), hp_growth)
	var damage_round_x: float = 0.0 if max_round <= 1.0 else clamp((PlayerData.now_round - 1.0) / (max_round - 1.0), 0.0, 1.0)
	var round_damage_mult: float = round_damage_curve.sample(damage_round_x) if round_damage_curve != null else 1.0
	damage_mult = PlayerData.level_damage * round_damage_mult

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
				var enemy_temp = enemy[i]
				
				if can_spawn == false:
					return
				
				# 并发上限：达上限则本类型本轮不再生成（预占 pending，落地后转 active）
				if not PoolManager.try_claim_spawn(enemy_temp.id):
					break
				
				var rand_position_num = ran.randi_range(0, cell_count) - 1
				var rand_position = tilemap.map_to_local(cells[rand_position_num])
				
				var p := _ensure_player()
				if p != null:
					while rand_position.distance_to(p.position) < 170:
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
