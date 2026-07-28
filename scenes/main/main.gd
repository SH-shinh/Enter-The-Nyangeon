extends Node2D

@export var bgm_first_cut: Array[AudioStream]
@export var bgm_loop: Array[AudioStream]

@onready var battle_room = $BattleRoom
@onready var round_manager = $RoundManager
@onready var game_mode_manager: Node = $game_mode_manager
@onready var BGM_timer: Timer = $BGMTimer

signal check

var bgm_num: int = 0

var floor_group: Array

var game_over: bool = false

var player: Node

func _ready() -> void:
	round_manager.enemy_clear.connect(enemy_clear_unit)
	round_manager.coin_clear.connect(coin_clear_unit)
	round_manager.bullet_clear.connect(bullet_clear_unit)
	round_manager.backlayer_clear.connect(backlayer_clear_unit)
	round_manager.item_clear.connect(item_clear_unit)
	round_manager.player_portal.connect(player_portal_unit)
	check.connect(check_enemies)
	GameEvents.first_round_add.connect(first_round)
	GameEvents.round_upgrade.connect(enemy_clear_unit)
	GameEvents.round_upgrade_end.connect(enemy_clear_unit)
	GameEvents.boss_round_start.connect(boss_bgm)
	GameEvents.boss_round_end.connect(boss_bgm_stop)
	GameEvents.pyroxenes_pick_up.connect(_on_bgm_timer_timeout)
	GameEvents.game_over.connect(game_over_true)

func game_over_true(player_dead: bool):
	game_over = true

func bgm_loop_play():
	if game_over == false:
		SoundManager.play_bgm(bgm_loop[bgm_num])

func first_round():
	SoundManager.game_end = false
	PoolManager.clear_pool()
	PlayerData.reset_date()
	
	game_mode_manager.get_player_game_mode()
	
	SoundManager.cut_finish.connect(bgm_loop_play)
	bgm_num = randi_range(1, bgm_first_cut.size() - 1)
	SoundManager.play_bgm_cut(bgm_first_cut[bgm_num])
	BGM_timer.start()
	
	PlayerData.get_player()
	PlayerData.get_player_base_ability()
	PlayerData.emit_set_player()
	PlayerData.update_player_ability()
	
	round_manager.first_round_start()
	
	SupportData.game_add_support()
	
	PoolManager.get_buff_box()

func get_player():
	player = get_tree().get_first_node_in_group("Player")

func check_enemies():
	PoolManager.check_enemies()

func enemy_clear_unit():
	for enemies in get_tree().get_first_node_in_group("EnemiesRoot").get_children():
		if enemies.is_in_group("Enemy") and !enemies.is_in_group("EnemyPart"):
			PoolManager.erase_pool(enemies.pool_id)
			enemies.queue_free()

func coin_clear_unit():
	for coins in get_tree().get_first_node_in_group("CoinRoot").get_children():
		if coins.is_in_group("PickItem"):
			PoolManager.erase_pool("coins")
			coins.coin_clear()

func item_clear_unit():
	for items in get_tree().get_first_node_in_group("CoinRoot").get_children():
		if items.is_in_group("HealthItem"):
			items.queue_free()

func bullet_clear_unit():
	for bullets in get_tree().get_first_node_in_group("BulletRoot").get_children():
		if bullets.is_in_group("EnemyBullet"):
			PoolManager.erase_pool(bullets.pool_id)
			bullets.queue_free()
		else:
			if bullets.get("is_idle") == 0:
				bullets.idle_state()

func backlayer_clear_unit():
	for textures in get_tree().get_first_node_in_group("FloorLayer").get_children():
		if textures.is_in_group("Texture"):
			textures.clear_pool()
			textures.queue_free()

func player_portal_unit():
	player = get_tree().get_first_node_in_group("Player")
	player.position = battle_room.position

func boss_bgm():
	SoundManager.bgm_fade_out()
	BGM_timer.stop()
	await get_tree().create_timer(1).timeout
	bgm_num = 0
	SoundManager.play_bgm_cut(bgm_first_cut[bgm_num])

func boss_bgm_stop():
	SoundManager.bgm_fade_out()

func _on_check_box_body_entered(body):
	if body.is_in_group("Enemy")  and !PoolManager.enemies_group.has(body):
		PoolManager.enemies_group.append(body)
		check.emit()

func _on_check_box_body_exited(body):
	if body.is_in_group("Enemy")  and PoolManager.enemies_group.has(body):
		PoolManager.enemies_group.remove_at(PoolManager.enemies_group.find(body))
		check.emit()


func _on_bgm_timer_timeout() -> void:
	var first_bgm = bgm_num
	bgm_num = randi_range(1, bgm_first_cut.size() - 1)
	if bgm_num != first_bgm:
		SoundManager.bgm_slow_fade_out(bgm_first_cut[bgm_num])
	BGM_timer.start()
