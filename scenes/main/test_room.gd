extends Node2D

signal check

@export var bgm_first_cut: Array[AudioStream]
@export var bgm_loop: Array[AudioStream]

@onready var blue_ball: CharacterBody2D = %blue_ball
@onready var red_ball: CharacterBody2D = %red_ball
@onready var item_text: Node2D = $TestRoomLayer/ItemText
@onready var use_name: Label = $TestRoomLayer/ItemText/Panel/use_name
@onready var animation_player: AnimationPlayer = $TestRoomLayer/ItemText/AnimationPlayer
@onready var battle_room: Marker2D = $BattleRoom

var bgm_num: int = 0

var player: Node
var ball_group: Array
var now_player_path: String = "res://scenes/player/momoi/momoi.tscn"

func _ready() -> void:
	check.connect(check_enemies)
	blue_ball.player_enter.connect(add_group)
	blue_ball.player_exit.connect(remove_group)
	red_ball.player_enter.connect(add_group)
	red_ball.player_exit.connect(remove_group)
	GameEvents.test_room_reset.connect(reset_data)
	GameEvents.teset_room_now_player.connect(updata_player_path)
	await get_tree().create_timer(0.1).timeout
	reset_data()
	test_room_start()

func check_enemies():
	PoolManager.check_enemies()

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
	GameEvents.emit_round_end()
	player = get_tree().get_first_node_in_group("Player")
	player.global_position = battle_room.global_position
	reset_clear_unit()
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

func _physics_process(delta: float) -> void:
	if !ball_group.is_empty():
		item_text.global_position = ball_group[0].global_position

func ball_count():
	if !ball_group.is_empty() and player != null:
		sort_enemy()
		for i in ball_group.size():
			if i == 0:
				use_name.text = ball_group[i].menu_name
				if item_text.visible == false:
					animation_player.play("show_text")
				ball_group[i].on_chose = true
			else:
				ball_group[i].on_chose = false

func sort_enemy():
	if ball_group.size() != 0:
		ball_group.sort_custom(
			func(x, y):
				return x.global_position.distance_to(player.global_position) < y.global_position.distance_to(player.global_position)
		)

func add_group(ball: Node):
	if !ball_group.has(ball):
		ball_group.push_back(ball)

func remove_group(ball: Node):
	if ball_group.has(ball):
		ball.on_chose = false
		ball_group.remove_at(ball_group.find(ball))
		if item_text.visible == true and ball_group.is_empty():
			animation_player.play_backwards("show_text")

func _on_timer_timeout():
	GameEvents.emit_global_time_count()
	ball_count()


func _on_check_box_body_entered(body: Node2D) -> void:
	if body.is_in_group("Enemy")  and !PoolManager.enemies_group.has(body):
		PoolManager.enemies_group.append(body)
		check.emit()


func _on_check_box_body_exited(body: Node2D) -> void:
	if body.is_in_group("Enemy")  and PoolManager.enemies_group.has(body):
		PoolManager.enemies_group.remove_at(PoolManager.enemies_group.find(body))
		check.emit()
