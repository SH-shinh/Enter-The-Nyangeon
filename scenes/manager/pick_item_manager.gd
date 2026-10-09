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
	player = get_tree().get_first_node_in_group("Player")
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
	var coin_return_value: int = coin_value * PlayerData.coin_return * player.stats.coin_mult
	if coin_return_value != 0:
		player.stats.coin += coin_return_value
		GameEvents.emit_player_coins_get(coin_return_value)
		SoundManager.play_sfx("CoinSounds")
	coin_value = 0

func add_medical_kit(spawn_position: Vector2):
	if ExtensionHooks.intercept(ExtensionHooks.medkit_spawn_gate, [self, spawn_position]):
		return
	if spawn_position == Vector2.ZERO and spawn_at_player and player != null:
		spawn_position = player.global_position
	if spawn_position == Vector2.ZERO:
		var ran = RandomNumberGenerator.new()
		var cells: Array = tilemap.get_used_cells(0)
		var rand_position_num = ran.randi_range(0, cells.size()) - 1
		var rand_position = tilemap.map_to_local(cells[rand_position_num])
		var ins = medical_kit.instantiate()
		ins.global_position = rand_position
		get_tree().get_first_node_in_group("CoinRoot").add_child(ins)
		ExtensionHooks.notify(ExtensionHooks.on_medkit_spawned, [ins])
	else:
		var ins = medical_kit.instantiate()
		ins.global_position = spawn_position
		get_tree().get_first_node_in_group("CoinRoot").add_child(ins)
		ExtensionHooks.notify(ExtensionHooks.on_medkit_spawned, [ins])

func medical_kit_spawn():
	if can_spawn == false:
		return
	if medical_time_num <= 0:
		if randf_range(0,1000) < (player.stats.luck + pick_luck) * spawn_rate_mult:
			pick_luck = 0
			add_medical_kit(Vector2.ZERO)
			medical_time_num = medical_cd_num
		else:
			pick_luck += 5

func _on_spawn_timer_timeout():
	medical_time_num -= 1
	medical_kit_spawn()
	pass # Replace with function body.
