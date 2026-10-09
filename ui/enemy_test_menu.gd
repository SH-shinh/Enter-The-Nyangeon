extends CanvasLayer

@export var spawn_position: Marker2D
@export var enemy_group: Array[EnemyCard]

var enemy_card_scene: PackedScene = preload("res://ui/test_enemy_card.tscn")
var player: Node

@onready var box: GridContainer = $Node2D/ScrollContainer/GridContainer
@onready var scroll_container: ScrollContainer = $Node2D/ScrollContainer
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var close: Button = $Node2D/Close

func _ready():
	GameEvents.get_player.connect(reset)
	Transition.left_end_start.connect(reset)
	close.mouse_entered.connect(button_sounds)
	# 点空白处（未落在卡片上）收起卡片文本；卡片点击会被 GridContainer 拦下，不会触发这里
	scroll_container.gui_input.connect(_on_scroll_gui_input)
	add_enemy_card()

func _on_scroll_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		# event.position 已是 ScrollContainer 本地坐标，换算到画布全局后判断是否落在某张卡上
		var gpos: Vector2 = scroll_container.get_global_transform_with_canvas() * event.position
		for card in box.get_children():
			if card is Control and card.get_global_rect().has_point(gpos):
				return
		GameEvents.emit_player_card_touch()

func _clear_card_text() -> void:
	GameEvents.emit_player_card_touch()

func reset():
	player = get_tree().get_first_node_in_group("Player")
	if self.visible == true:
		_clear_card_text()
		self.visible = false

func add_enemy_card():
	var enemies: Array = []
	enemies.append_array(enemy_group)
	for e in ModManager.get_content("enemies"):
		if e != null and not enemies.has(e):
			enemies.append(e)
	if enemies.is_empty():
		return
	for enemy in enemies:
		if enemy == null:
			continue
		var card = enemy_card_scene.instantiate()
		box.add_child(card)
		card.setup(self, enemy)

func spawn_enemy(enemy: EnemyCard):
	if spawn_position == null or enemy == null:
		return
	var test_room = get_parent()
	if test_room != null and test_room.has_method("spawn_test_enemy"):
		test_room.spawn_test_enemy(enemy, spawn_position.global_position)

func refresh_enemies():
	var test_room = get_parent()
	if test_room != null and test_room.has_method("refresh_enemies"):
		test_room.refresh_enemies()

func _unhandled_input(event):
	if event.is_action_pressed("use"):
		if self.visible == true:
			SoundManager.play_sfx("UISounds2")
			player.can_control = true
			GameEvents.emit_camera_reset()
			animation_player.play_backwards("new_animation")
			await animation_player.animation_finished
			GameEvents.emit_ui_visible(true)
			_clear_card_text()
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

func _on_close_pressed() -> void:
	if self.visible == true:
		SoundManager.play_sfx("UISounds2")
		player.can_control = true
		GameEvents.emit_camera_reset()
		animation_player.play_backwards("new_animation")
		await animation_player.animation_finished
		GameEvents.emit_ui_visible(true)
		_clear_card_text()
		self.visible = false

func _on_refresh_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	_clear_card_text()
	refresh_enemies()

func _on_button_pressed() -> void:
	pass

func _on_button_2_pressed() -> void:
	pass
