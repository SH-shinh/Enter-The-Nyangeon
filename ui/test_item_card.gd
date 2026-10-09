extends PanelContainer

@onready var texture_rect = $TextureRect
@onready var item_text_2 = %ItemText2
@onready var item_text_3 = %ItemText3
@onready var item_text_4: Label = %ItemText4
@onready var item_text = %ItemText
@onready var text_show = $Text
@onready var button: Button = $Button

var upgrade_manager: Node
var up_c: AbilityUpgrade
var text_is_show: bool = false
var on_touch: bool = false
var num: int = 0

var touch_index: int = -1
var touch_start_position: Vector2 = Vector2.ZERO
const TAP_MAX_DISTANCE: float = 14.0

func _ready():
	GameEvents.player_card_touch.connect(touch_out)
	GameEvents.get_player.connect(_reset)
	GameEvents.test_room_button_close.connect(close_button)
	GameEvents.test_room_reset.connect(open_button)
	mouse_entered.connect(show_text)
	mouse_exited.connect(hide_text)

func open_button():
	button.mouse_filter = Control.MOUSE_FILTER_PASS

func close_button():
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _physics_process(_delta: float) -> void:
	if text_is_show == true:
		if on_touch == false:
			text_show.global_position = get_global_mouse_position()
		else:
			text_show.global_position = self.global_position

func _reset():
	num = up_c.order_num

func touch_out():
	if on_touch == true:
		on_touch = false
		text_show.visible = false

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

func get_card(upgrade_card: AbilityUpgrade):
	up_c = upgrade_card
	# 稀有度背景：纯色 + 圆角 + 描边（rare 2 金边高亮）
	var sb := StyleBoxFlat.new()
	sb.bg_color = AbilityUpgrade.RARITY_COLORS[up_c.rare].from_hsv(AbilityUpgrade.RARITY_COLORS[up_c.rare].h, 0.65, 0.7)
	sb.set_content_margin_all(1)
	sb.set_corner_radius_all(2)
	sb.set_border_width_all(1)
	sb.border_color = sb.bg_color.from_hsv(sb.bg_color.h, 0.9, 0.9).lightened(0.35)
	add_theme_stylebox_override("panel", sb)
	texture_rect.texture = up_c.icon
	item_text_4.text = up_c.id + "_name"
	item_text.text = up_c.id + "_description"
	item_text_2.text = up_c.id + "_forward"
	item_text_3.text = up_c.id + "_negative"
	num = up_c.order_num

func add_card():
	upgrade_manager.apply_upgrade(up_c)

func _on_button_pressed():
	on_touch = false
	text_show.visible = false
	text_is_show = false
	if num == 0:
		SoundManager.play_sfx("ButtonSounds2")
	else:
		if num > 0:
			num -= 1
		SoundManager.play_sfx("ButtonSounds")
		add_card()

func _on_button_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			# 同一张卡同一时刻只跟踪一根手指
			if touch_index != -1:
				return
			touch_index = event.index
			touch_start_position = event.position
		else:
			if event.index != touch_index:
				return
			var moved: float = event.position.distance_to(touch_start_position)
			touch_index = -1
			# 位移超过阈值视为滚动拖动：不预览、不生效
			if moved > TAP_MAX_DISTANCE:
				return
			if on_touch == false:
				_preview_text()
			else:
				_on_button_pressed()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_button_pressed()
