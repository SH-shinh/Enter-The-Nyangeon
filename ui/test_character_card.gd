extends PanelContainer

@onready var sprite_2d: Sprite2D = $ColorRect/Sprite2D
@onready var button: Button = $Button
@onready var ps_text: Label = %PSText
@onready var text_show: Node2D = $Text

var player_card: PlayerCard
var player_id: String
var player_path: String
var on_touch: bool = false
var text_is_show: bool = false

var touch_index: int = -1
var touch_start_pos: Vector2 = Vector2.ZERO
const TAP_MAX_DISTANCE: float = 14.0
static var _selection_locked: bool = false

func _ready() -> void:
	GameEvents.test_room_button_close.connect(close_button)
	GameEvents.test_room_reset.connect(open_button)
	GameEvents.player_card_touch.connect(touch_out)
	mouse_entered.connect(show_text)
	mouse_exited.connect(hide_text)

func _physics_process(delta: float) -> void:
	if text_is_show == true:
		if on_touch == false:
			text_show.global_position = get_global_mouse_position()
		else:
			text_show.global_position = self.global_position

func open_button():
	button.mouse_filter = 1

func close_button():
	button.mouse_filter = 2
	touch_index = -1

func load_player_card():
	if player_card != null:
		sprite_2d.texture = LazyTexture.load_uncached(player_card.sprite_path)
		player_id = player_card.id
		ps_text.text = _ps_text(0)
		player_path = player_card.scene_path
		if player_path == "":
			player_path = "res://scenes/player/" + player_id + "/" + player_id + ".tscn"


# 本地化缺失时回退到角色描述，避免显示原始键（如 xxx_ps_0）
func _ps_text(idx: int) -> String:
	if player_card == null:
		return ""
	var key := player_card.id + "_ps_" + str(idx)
	var t := tr(key)
	return t if t != key else str(player_card.description)

func touch_out():
	if on_touch == true:
		on_touch = false
		text_show.visible = false
		text_is_show = false

func _preview_text():
	# 先广播隐藏其它卡的文本，再置自身状态，避免被自身的 touch_out 清掉
	GameEvents.emit_player_card_touch()
	on_touch = true
	text_show.visible = true
	text_is_show = true

func show_text():
	SoundManager.play_sfx("ButtonSounds2")
	text_show.visible = true
	text_is_show = true

func hide_text():
	text_show.visible = false
	text_is_show = false

func _on_button_pressed() -> void:
	on_touch = false
	text_show.visible = false
	text_is_show = false
	if _selection_locked:
		return
	_selection_locked = true
	SoundManager.play_sfx("ButtonSounds")
	get_tree().paused = true
	GameEvents.emit_test_room_button_close()
	GameEvents.emit_teset_room_now_player(player_path)
	Transition.play_left_start()
	await Transition.left_end_start
	if not ExtensionHooks.intercept(ExtensionHooks.local_player_change_gate, [player_path, Vector2.ZERO]):
		var player = get_tree().get_first_node_in_group("Player")
		if player != null:
			player.queue_free()
		var path = load(player_path)
		var ins = path.instantiate()
		get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)
	Transition.play_left_end()
	await Transition.animation_player.animation_finished
	GameEvents.emit_test_room_reset()
	get_tree().paused = false
	_selection_locked = false

func _on_button_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			# 同一张卡同一时刻只跟踪一根手指
			if touch_index != -1:
				return
			touch_index = event.index
			touch_start_pos = event.position
		else:
			if event.index != touch_index:
				return
			var moved: float = event.position.distance_to(touch_start_pos)
			touch_index = -1
			# 位移超过阈值视为滚动拖动：不预览、不选中
			if moved > TAP_MAX_DISTANCE:
				return
			if on_touch == false:
				_preview_text()
			else:
				_on_button_pressed()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_button_pressed()
