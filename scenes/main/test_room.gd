extends Node2D

@export var bgm_first_cut: Array[AudioStream]
@export var bgm_loop: Array[AudioStream]

@onready var battle_room: Marker2D = $BattleRoom

var bgm_num: int = 0

var _reset_token: int = 0

var player: Node
var now_player_path: String = "res://scenes/player/momoi/momoi.tscn"

var initial_enemies: Array = []
var spawned_anim_scene: PackedScene = preload("res://script/spawn_anim.tscn")

func _ready() -> void:
	initial_enemies = get_tree().get_first_node_in_group("EnemiesRoot").get_children()
	GameEvents.test_room_reset.connect(reset_data)
	GameEvents.teset_room_now_player.connect(updata_player_path)
	await get_tree().create_timer(0.1).timeout
	reset_data()
	test_room_start()

func test_room_start():
	SoundManager.cut_finish.connect(bgm_loop_play)
	bgm_num = randi_range(0, bgm_first_cut.size() - 1)
	SoundManager.play_bgm_cut(bgm_first_cut[bgm_num])
	PoolManager.get_buff_box()

func bgm_loop_play():
	SoundManager.play_bgm(bgm_loop[bgm_num])

func updata_player_path(player_path: String):
	now_player_path = player_path

func reset_data():
	_reset_token += 1
	var token := _reset_token
	GameEvents.emit_round_end()
	player = PlayerRef.resolve(self)
	if player == null:
		# LAN：本地玩家由 change_scene 延迟 add_child，0.1s 时可能尚未入组；
		# 有界等待后再完成本房初始化，避免跳过 reset_date/get_player_base_ability
		# （否则 base_* 为默认 0，首次获取道具时属性被重算成默认值）。
		for _i in 30:
			await get_tree().process_frame
			if token != _reset_token:
				return
			player = PlayerRef.resolve(self)
			if player != null:
				break
		if player == null or token != _reset_token:
			return
	player.global_position = battle_room.global_position
	reset_clear_unit()
	refresh_enemies()
	connect_player_protection()
	PlayerData.reset_date()
	GameEvents.emit_first_round_add()
	PlayerData.get_player()
	PlayerData.get_player_base_ability()
	PlayerData.emit_set_player()
	PlayerData.update_player_ability()
	GameEvents.emit_get_player()
	GameEvents.emit_round_start()
	PoolManager.clear_pool()
	PlayerData.on_test_room = true

func reset_clear_unit():
	for node in get_tree().get_first_node_in_group("PlayerRoot").get_children():
		if !node.is_in_group("Player"):
			node.queue_free()
	for bullet in get_tree().get_first_node_in_group("BulletRoot").get_children():
		if bullet.get("pool_id") != null and str(bullet.pool_id) != "":
			PoolManager.erase_pool(str(bullet.pool_id))
		bullet.queue_free()
	for equip in get_tree().get_first_node_in_group("EquipLayer").get_children():
		equip.queue_free()
	for summoned in get_tree().get_nodes_in_group("Summoned"):
		summoned.queue_free()
	for se in get_tree().get_first_node_in_group("SELayer").get_children():
		se.queue_free()
	for foreground in get_tree().get_first_node_in_group("ForegroundLayer").get_children():
		foreground.queue_free()
	for floor in get_tree().get_first_node_in_group("FloorLayer").get_children():
		floor.queue_free()
	for prop in get_tree().get_nodes_in_group("SceneProp"):
		prop.queue_free()

func refresh_enemies():
	var root = get_tree().get_first_node_in_group("EnemiesRoot")
	if root == null:
		return
	PoolManager.clear_active_enemies()
	for node in root.get_children():
		if not initial_enemies.has(node):
			node.queue_free()
	for node in initial_enemies:
		if node == null or not is_instance_valid(node):
			continue
		if node.has_method("reset_position"):
			node.reset_position()
		if node.get("stats") != null:
			node.stats.spawn_hp()
		if node.has_method("active_state"):
			node.active_state()

func spawn_test_enemy(enemy: EnemyCard, position: Vector2):
	if enemy == null or enemy.body == null:
		return
	var spawn_anim = spawned_anim_scene.instantiate()
	spawn_anim.position = position
	spawn_anim.hp_mult = 1
	spawn_anim.damage_mult = 1
	get_tree().get_first_node_in_group("EnemiesRoot").add_child(spawn_anim)
	spawn_anim.enemy_spawn_anim(enemy)

func connect_player_protection():
	if player != null and player.get("stats") != null:
		if not player.stats.hp_changed.is_connected(protect_player):
			player.stats.hp_changed.connect(protect_player)

func protect_player():
	if player != null and is_instance_valid(player) and player.get("stats") != null:
		if player.stats.hp <= 0:
			player.stats.hp = player.stats.max_hp

func _on_timer_timeout():
	GameEvents.emit_global_time_count()
