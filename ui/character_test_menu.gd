extends CanvasLayer

@export var player_group: Array[PlayerCard]

var character_card: PackedScene = preload("res://ui/test_character_card.tscn")
var player: Node

@onready var box: GridContainer = $Node2D/ScrollContainer/GridContainer
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var close: Button = $Node2D/Close
@onready var kei_p: SupportCard = preload("res://resources/support/kei.tres")
@onready var support_ui: Node2D = $Node2D/support_ui

var close_to_reset: bool = false
var now_player_path: String = "res://scenes/player/momoi/momoi.tscn"

func _ready():
	GameEvents.get_player.connect(reset)
	GameEvents.teset_room_now_player.connect(updata_player_path)
	Transition.left_end_start.connect(reset)
	close.mouse_entered.connect(button_sounds)
	support_ui.test_menu_changed.connect(is_reset)
	add_player_card()

func is_reset():
	close_to_reset = true

func updata_player_path(player_path: String):
	now_player_path = player_path

func reset_player():
	get_tree().paused = true
	GameEvents.emit_test_room_button_close()
	Transition.play_left_start()
	await Transition.left_end_start
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
	SupportData.game_add_support()

func close_and_reset():
	if close_to_reset == true:
		close_to_reset = false
		reset_player()

func reset():
	player = get_tree().get_first_node_in_group("Player")
	if self.visible == true:
		self.visible = false

func add_player_card():
	if !player_group.is_empty():
		for i in player_group.size():
			var card_ins = character_card.instantiate()
			box.add_child(card_ins)
			card_ins.player_card = player_group[i]
			card_ins.load_player_card()

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
			close_and_reset()

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
		self.visible = false
		close_and_reset()

func _on_close_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_on_close_pressed()


func _on_button_pressed() -> void:
	SupportData.game_support = kei_p
	SupportData.game_add_support()
