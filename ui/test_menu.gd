extends Node


@export var upgrade_manager: Node
@export var enemy: EnemyCard
@export var spawn_position: Marker2D
@onready var scroll_container = $Node2D/ScrollContainer
@onready var box = $Node2D/ScrollContainer/GridContainer
@onready var enemy_spawn_anim = preload("res://script/spawn_anim.tscn")
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var reset_button: Button = $Node2D/Reset
@onready var close: Button = $Node2D/Close

var test_card = preload("res://ui/test_item_card.tscn")
var upgrades_pool_c: Array[AbilityUpgrade] = []

var player: Node
var now_player_path: String = "res://scenes/player/momoi/momoi.tscn"

func _ready():
	GameEvents.get_player.connect(reset)
	Transition.left_end_start.connect(reset)
	GameEvents.teset_room_now_player.connect(updata_player_path)
	GameEvents.test_room_button_close.connect(close_button)
	GameEvents.test_room_reset.connect(open_button)
	reset_button.mouse_entered.connect(button_sounds)
	close.mouse_entered.connect(button_sounds)
	add_card()

func open_button():
	reset_button.mouse_filter = 0

func close_button():
	reset_button.mouse_filter = 2

func updata_player_path(player_path: String):
	now_player_path = player_path

func reset():
	player = get_tree().get_first_node_in_group("Player")
	if self.visible == true:
		self.visible = false

func add_card():
	upgrades_pool_c = upgrade_manager.upgrade_pool.duplicate()
	# 直接并入 mod 道具（不依赖 upgrade_manager 的注入时序/快照）
	for u in ModManager.get_content("upgrades"):
		if u != null and not upgrades_pool_c.has(u):
			upgrades_pool_c.append(u)
	# 按稀有度升序稳定分桶排序；同稀有度保持 upgrade_pool 原始顺序
	var sorted_pool: Array[AbilityUpgrade] = []
	for r in 3:
		for up in upgrades_pool_c:
			if up.rare == r:
				sorted_pool.append(up)
	upgrades_pool_c = sorted_pool
	for i in upgrades_pool_c.size():
		var ins = test_card.instantiate()
		box.add_child(ins)
		ins.upgrade_manager = upgrade_manager
		ins.get_card(upgrades_pool_c[i])

func _unhandled_input(event):
	if event.is_action_pressed("use"):
		if self.visible == true:
			SoundManager.play_sfx("UISounds2")
			player.can_control = true
			GameEvents.emit_camera_reset()
			animation_player.play_backwards("new_animation")
			await animation_player.animation_finished
			GameEvents.emit_ui_visible(true)
			self.visible = false

func show_menu():
	if self.visible == false:
		SoundManager.play_sfx("UISounds1")
		player.can_control = false
		animation_player.play("new_animation")
		GameEvents.emit_ui_visible(false)
		self.visible = true

func button_sounds():
	SoundManager.play_sfx("ButtonSounds2")

func _on_button_pressed():
	pass

func _on_button_2_pressed():
	pass
	var spawn_anim = enemy_spawn_anim.instantiate()
	spawn_anim.position = spawn_position.global_position
	spawn_anim.hp_mult = 1
	spawn_anim.damage_mult = 1
	get_tree().get_first_node_in_group("EnemiesRoot").add_child(spawn_anim)
	spawn_anim.enemy_spawn_anim(enemy)


func _on_reset_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	get_tree().paused = true
	GameEvents.emit_test_room_button_close()
	Transition.play_left_start()
	await Transition.left_end_start
	if not ExtensionHooks.intercept(ExtensionHooks.local_player_change_gate, [now_player_path, Vector2.ZERO]):
		var player = get_tree().get_first_node_in_group("Player")
		if player != null:
			player.queue_free()
		var path = load(now_player_path)
		var ins = path.instantiate()
		get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)
	Transition.play_left_end()
	await Transition.animation_player.animation_finished
	GameEvents.emit_test_room_reset()
	get_tree().paused = false


func _on_close_pressed() -> void:
	if self.visible == true:
		SoundManager.play_sfx("UISounds2")
		player.can_control = true
		GameEvents.emit_camera_reset()
		animation_player.play_backwards("new_animation")
		await animation_player.animation_finished
		GameEvents.emit_ui_visible(true)
		self.visible = false
