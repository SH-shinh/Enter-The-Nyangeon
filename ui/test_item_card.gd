extends PanelContainer

@onready var texture_rect = $TextureRect
@onready var button: Button = $Button

var upgrade_manager: Node
var up_c: AbilityUpgrade
var on_touch: bool = false
var _tooltip: HoverTooltipBinding
var num: int = 0

var touch_index: int = -1
var touch_start_position: Vector2 = Vector2.ZERO
const TAP_MAX_DISTANCE: float = 14.0
var _mouse_pressed := false
var _mouse_dragged := false
var _mouse_start_position := Vector2.ZERO
var _mouse_sequence: int = 0

func _ready():
	GameEvents.player_card_touch.connect(touch_out)
	GameEvents.get_player.connect(_reset)
	GameEvents.test_room_button_close.connect(close_button)
	GameEvents.test_room_reset.connect(open_button)
	mouse_entered.connect(func(): SoundManager.play_sfx("ButtonSounds2"))
	_tooltip = HoverTooltipBinding.bind(self, _tooltip_content, func(): return button.mouse_filter != Control.MOUSE_FILTER_IGNORE and not button.disabled, func(): on_touch = false)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			_clear_mouse_press()
	)

func _clear_mouse_press() -> void:
	_mouse_sequence += 1
	_mouse_pressed = false
	_mouse_dragged = false

func _clear_mouse_press_if_current(sequence: int) -> void:
	if sequence == _mouse_sequence:
		_clear_mouse_press()

func _input(event: InputEvent) -> void:
	if not _mouse_pressed:
		return
	# 先于 ScrollBox/GUI 消费事件观察视口位移；滚动后卡片本地坐标会改变。
	if event is InputEventMouseMotion:
		_mouse_dragged = _mouse_dragged or event.position.distance_to(_mouse_start_position) > TAP_MAX_DISTANCE
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_mouse_dragged = _mouse_dragged or event.canceled or event.position.distance_to(_mouse_start_position) > TAP_MAX_DISTANCE
		# GUI 若未收到释放（例如在列表外松手），也不能残留待确认状态。
		_clear_mouse_press_if_current.call_deferred(_mouse_sequence)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_clear_mouse_press()

func open_button():
	button.mouse_filter = Control.MOUSE_FILTER_PASS

func close_button():
	_tooltip.dismiss()
	_clear_mouse_press()
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _reset():
	num = up_c.order_num

func touch_out() -> void:
	_tooltip.dismiss()

func _preview_text(index: int = -1) -> void:
	GameEvents.emit_player_card_touch()
	on_touch = true
	_tooltip.preview("touch", index)

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
	num = up_c.order_num

func add_card():
	upgrade_manager.apply_upgrade(up_c)

func _on_button_pressed():
	on_touch = false
	_tooltip.dismiss()
	if num == 0:
		SoundManager.play_sfx("ButtonSounds2")
	else:
		if num > 0:
			num -= 1
		SoundManager.play_sfx("ButtonSounds")
		add_card()

func _on_button_gui_input(event: InputEvent) -> void:
	if button.disabled or button.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		_clear_mouse_press()
		return
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
			if event.canceled or _tooltip.touch_was_dragged(event.index) or moved > TAP_MAX_DISTANCE:
				return
			if on_touch == false:
				_preview_text(event.index)
			else:
				_on_button_pressed()
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT or event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if event.pressed:
			_mouse_sequence += 1
			_mouse_pressed = true
			_mouse_dragged = false
			_mouse_start_position = button.get_global_transform_with_canvas() * event.position
		else:
			var activate: bool = _mouse_pressed and not _mouse_dragged and not event.canceled and Rect2(Vector2.ZERO, button.size).has_point(event.position)
			_clear_mouse_press()
			if activate:
				_on_button_pressed()

func _tooltip_content() -> Array:
	if up_c == null:
		return []
	return [
		{"text": up_c.id + "_name", "role": "title"},
		# 描述/正效果/负效果允许有意留空：optional 段无译文时整段跳过，不显示键名。
		{"text": up_c.id + "_description", "optional": true},
		{"text": up_c.id + "_forward", "role": "positive", "optional": true},
		{"text": up_c.id + "_negative", "role": "negative", "optional": true},
	]
