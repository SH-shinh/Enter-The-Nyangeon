extends Node

@export var medical_kit: PackedScene
@onready var spawn_timer = $SpawnTimer

@export var medical_cd_num: int = 10
@export var spawn_at_player: bool = false #true 时医疗箱必定生成在玩家脚下（支援 serina）
@export var spawn_rate_mult: float = 1.0 #生成概率乘区（阈值加成，支援 serina 覆写为 2.0）
var medical_time_num: int = 0
var can_spawn: bool = false
var tilemap = null
var pick_luck: int = 0
var player: Node
var coin_value: int = 0

func _ready():
	GameEvents.round_start.connect(spawn_start)
	GameEvents.get_player.connect(get_player_and_map)
	GameEvents.boss_round_end.connect(spawn_stop)
	GameEvents.round_end.connect(spawn_stop)
	GameEvents.coin_return_count.connect(coin_count)
	GameEvents.round_upgrade.connect(coin_add)
	medical_time_num = medical_cd_num

func get_player_and_map():
	player = PlayerRef.resolve(self)
	tilemap = get_tree().get_first_node_in_group("Map")

func spawn_start():
	coin_value = 0
	can_spawn = true
	spawn_timer.start()

func spawn_stop():
	can_spawn = false
	spawn_timer.stop()

func coin_count(coins: int):
	coin_value += coins

func coin_add():
	player = PlayerRef.ensure(self, player)
	if player != null:
		var coin_return_value: int = coin_value * PlayerData.coin_return * player.stats.coin_mult
		if coin_return_value != 0:
			player.stats.coin += coin_return_value
			GameEvents.emit_player_coins_get(coin_return_value)
			SoundManager.play_sfx("CoinSounds")
	coin_value = 0

func add_medical_kit(spawn_position: Vector2):
	if ExtensionHooks.intercept_named("medkit_spawn_gate", [self, spawn_position]):
		return
	player = PlayerRef.ensure(self, player)
	var pos := spawn_position
	if pos == Vector2.ZERO and spawn_at_player and player != null:
		pos = player.global_position
	if pos == Vector2.ZERO:
		pos = _random_medkit_position()
	if not pos.is_finite():
		return
	pos = EnemyNavField.safe_pickup_point(pos)
	if not pos.is_finite():
		return
	_spawn_medical_kit(pos)


# 随机医疗包：先按地面 tile 取候选，墙体/障碍命中则重试；都失败时退回最近安全点。
func _random_medkit_position() -> Vector2:
	if tilemap == null or not is_instance_valid(tilemap) or not tilemap.has_method("get_used_cells"):
		return Vector2.INF
	var cells: Array = tilemap.get_used_cells(0)
	if cells.is_empty():
		return Vector2.INF
	var nav_ready := EnemyNavField.ensure_topology()
	var last := Vector2.ZERO
	for attempt in 16:
		var idx := randi_range(0, cells.size() - 1)
		var cell = cells[idx]
		if not (cell is Vector2i):
			continue
		var candidate: Vector2 = tilemap.to_global(tilemap.map_to_local(cell))
		last = candidate
		if nav_ready and EnemyNavField.is_solid(candidate):
			continue
		return candidate
	if nav_ready:
		return EnemyNavField.safe_pickup_point(last)
	return last


func _spawn_medical_kit(pos: Vector2) -> void:
	if medical_kit == null:
		return
	var root := get_tree().get_first_node_in_group("CoinRoot")
	if root == null:
		return
	var ins = medical_kit.instantiate()
	if ins == null:
		return
	root.add_child(ins)
	if ins is Node2D:
		(ins as Node2D).global_position = pos
	ExtensionHooks.notify_named("on_medkit_spawned", [ins])

func medical_kit_spawn():
	player = PlayerRef.ensure(self, player)
	if can_spawn == false:
		return
	var luck: float = float(player.stats.luck) if player != null else 0.0
	if medical_time_num <= 0:
		if randf_range(0,1000) < (luck + pick_luck) * spawn_rate_mult:
			pick_luck = 0
			add_medical_kit(Vector2.ZERO)
			medical_time_num = medical_cd_num
		else:
			pick_luck += 5

func _on_spawn_timer_timeout():
	medical_time_num -= 1
	medical_kit_spawn()
	pass # Replace with function body.
