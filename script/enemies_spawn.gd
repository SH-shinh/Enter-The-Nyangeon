extends Node2D

@export var boss_round: bool = false
# 普通回合中途乱入：复用 Boss 刷怪场景，但不切换回合计时。
var is_intruder: bool = false
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
	var growth_override: Curve = null
	if PlayerData.current_level != null:
		growth_override = PlayerData.current_level.non_endless_hp_growth_curve
	var multipliers := EnemyScaling.hp_damage_multipliers(
		PlayerData.now_round,
		max_round,
		boss_round,
		PlayerData.on_endless,
		PlayerData.level_hp,
		PlayerData.level_damage,
		endless_hp,
		endless_boss_hp,
		endless_damage,
		round_hp_curve,
		round_boss_hp_curve,
		round_damage_curve,
		hp_growth_curve,
		PlayerData.game_mode.has("hujiu"),
		growth_override
	)
	hp_mult = float(multipliers.get("hp", 1.0))
	damage_mult = float(multipliers.get("damage", 1.0))

func round_count(x: float, y:float):
	return pow(x, y)

func _resolve_boss_position() -> Vector2:
	if boss_position != Vector2.ZERO:
		return boss_position
	var center := get_tree().get_first_node_in_group("CenterPosition")
	if center is Node2D:
		return (center as Node2D).global_position
	return Vector2.ZERO

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
		
		spawn_anim.position = _resolve_boss_position()
		spawn_anim.hp_mult = hp_mult
		spawn_anim.damage_mult = damage_mult
		spawn_anim.is_boss = true
		spawn_anim.is_intruder = is_intruder
		if is_intruder:
			spawn_anim.add_to_group("BossIntruder")
		spawn_anim.active_state()
		spawn_anim.enemy_spawn_anim(enemy_temp)
		GameEvents.emit_enemy_spawn()
		enemy_spawn_time_copy[i] = enemy_spawn_time[i]

func enemy_spawn():
	var ran = RandomNumberGenerator.new()
	var cells: Array = tilemap.get_used_cells(0)
	var nav_ready := EnemyNavField.ensure_topology()
	for i in enemy.size():
		if enemy_spawn_time_copy[i] <= 0:
			for n in floor(enemy_spawn_num[i] + (time_mult * time_mult * num_mult)) * round_mult:
				var enemy_temp = enemy[i]
				
				if can_spawn == false:
					return
				
				# 并发上限：达上限则本类型本轮不再生成（预占 pending，落地后转 active）
				if not PoolManager.try_claim_spawn(enemy_temp.id):
					break
				
				var p := _ensure_player()
				var spawn_position := _pick_safe_spawn_position(ran, p, cells, nav_ready)
				if not spawn_position.is_finite():
					# 找不到不与障碍冲突的位置：释放预占，等下一次生成时机，绝不塞进墙里。
					PoolManager.release_spawn_claim(enemy_temp.id)
					break
				
				var spawn_anim = PoolManager.get_pool("spawn_anim")
				if spawn_anim == null or spawn_anim.is_idle == 0:
					spawn_anim = enemy_spawn_anim.instantiate()
					get_tree().get_first_node_in_group("EnemiesRoot").add_child(spawn_anim)
				
				spawn_anim.position = spawn_position
				spawn_anim.hp_mult = hp_mult
				spawn_anim.damage_mult = damage_mult
				spawn_anim.active_state()
				spawn_anim.enemy_spawn_anim(enemy_temp)
				GameEvents.emit_enemy_spawn()
			enemy_spawn_time_copy[i] = enemy_spawn_time[i] * mode_mult


func _pick_safe_spawn_position(ran: RandomNumberGenerator, p: Node, cells: Array, nav_ready: bool) -> Vector2:
	var cell_count := cells.size()
	if cell_count <= 0:
		return Vector2(INF, INF)
	var last := Vector2.ZERO
	for attempt in 16:
		var idx := ran.randi_range(0, cell_count - 1)
		var pos: Vector2 = tilemap.map_to_local(cells[idx])
		last = pos
		if p != null and pos.distance_to(p.position) < 170.0:
			continue
		if nav_ready and not EnemyNavField.is_body_safe(pos, 1):
			continue
		return pos
	if nav_ready:
		var safe := EnemyNavField.nearest_body_safe_point(last, 1)
		if safe.is_finite() and (p == null or safe.distance_to(p.position) >= 170.0):
			return safe
	return Vector2(INF, INF)

func _on_enemy_spawn_cd_time_timeout():
	if can_spawn == false:
		return
	enemy_spawn()
	for i in enemy_spawn_time.size():
		enemy_spawn_time_copy[i] -= 1
