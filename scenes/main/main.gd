extends Node2D

const FLOATING_TEXT: PackedScene = preload("res://ui/floating_text.tscn")

@export var bgm_first_cut: Array[AudioStream]
@export var bgm_loop: Array[AudioStream]

@onready var battle_room = $BattleRoom
@onready var round_manager = $RoundManager
@onready var game_mode_manager: Node = $game_mode_manager
@onready var BGM_timer: Timer = $BGMTimer

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
	GameEvents.first_round_add.connect(first_round)
	GameEvents.round_upgrade.connect(enemy_clear_unit)
	GameEvents.round_upgrade_end.connect(enemy_clear_unit)
	GameEvents.boss_round_start.connect(boss_bgm)
	GameEvents.boss_round_end.connect(boss_bgm_stop)
	GameEvents.pyroxenes_pick_up.connect(_on_bgm_timer_timeout)
	GameEvents.game_over.connect(game_over_true)

func game_over_true(_player_dead: bool):
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
	if PlayerData.player == null:
		# 防御：玩家尚未入组时不要用默认 base_* 重算（否则属性会塌成默认值）
		for _i in 30:
			await get_tree().process_frame
			PlayerData.get_player()
			if PlayerData.player != null:
				break
		if PlayerData.player == null:
			push_warning("[main] first_round: player not ready, skip base capture")
			return
	PlayerData.get_player_base_ability()
	PlayerData.emit_set_player()
	PlayerData.update_player_ability()
	
	var start_local_round: bool = true
	if ExtensionHooks.first_round_start_gate.is_valid():
		start_local_round = bool(ExtensionHooks.first_round_start_gate.call())
	if start_local_round:
		round_manager.first_round_start()
	
	SupportData.game_add_support()
	
	PoolManager.get_buff_box()

func get_player():
	player = PlayerRef.resolve(self)

func enemy_clear_unit():
	var total_coin: int = 0
	for enemies in get_tree().get_first_node_in_group("EnemiesRoot").get_children():
		if enemies.is_in_group("Enemy") and !enemies.is_in_group("EnemyPart"):
			if enemies.is_in_group("Converted") and enemies.has_method("settle_converted_clear"):
				total_coin += enemies.settle_converted_clear()
			PoolManager.erase_pool(enemies.pool_id)
			enemies.queue_free()
	if total_coin > 0:
		_show_converted_clear_coin(total_coin)

# 清场时被策反敌人金币总额：在玩家处飘一次白→粉提示，并播放一次金币音效
func _show_converted_clear_coin(value: int) -> void:
	player = get_tree().get_first_node_in_group("Player")
	if player == null:
		return
	SoundManager.play_sfx("CoinSounds")
	var ft: Node2D = PoolManager.get_pool("floating_text")
	if ft == null or ft.is_idle == 0:
		ft = FLOATING_TEXT.instantiate() as Node2D
		get_tree().get_first_node_in_group("ForegroundLayer").add_child(ft)
	ft.global_position = player.global_position + (Vector2.UP * randf_range(30, 50))
	ft.set_style(Color(1, 1, 1), 24)
	ft.play_anim(Color(1, 1, 1), Color(0.986, 0.638, 0.855))
	ft.start("+" + str(value))

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
	player = PlayerRef.ensure(self, player)
	if player == null:
		return
	player.position = battle_room.position

func boss_bgm():
	SoundManager.bgm_fade_out()
	BGM_timer.stop()
	await get_tree().create_timer(1).timeout
	bgm_num = 0
	SoundManager.play_bgm_cut(bgm_first_cut[bgm_num])

func boss_bgm_stop():
	SoundManager.bgm_fade_out()

func _on_bgm_timer_timeout() -> void:
	var first_bgm = bgm_num
	bgm_num = randi_range(1, bgm_first_cut.size() - 1)
	if bgm_num != first_bgm:
		SoundManager.bgm_slow_fade_out(bgm_first_cut[bgm_num])
	BGM_timer.start()
