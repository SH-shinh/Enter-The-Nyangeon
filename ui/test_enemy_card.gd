extends PanelContainer

@onready var texture_rect = $TextureRect
@onready var button: Button = $Button
@onready var sprite_2d = $TextureRect/Sprite2D

var menu: Node
var enemy_card: EnemyCard
var on_touch: bool = false
var _tooltip: HoverTooltipBinding

var touch_index: int = -1
var touch_start_position: Vector2 = Vector2.ZERO
const TAP_MAX_DISTANCE: float = 14.0

func _ready():
	GameEvents.player_card_touch.connect(touch_out)
	mouse_entered.connect(func(): SoundManager.play_sfx("ButtonSounds2"))
	_tooltip = HoverTooltipBinding.bind(self, _tooltip_content, func(): return button.mouse_filter != Control.MOUSE_FILTER_IGNORE and not button.disabled, func(): on_touch = false)

func setup(p_menu: Node, p_enemy: EnemyCard):
	menu = p_menu
	enemy_card = p_enemy
	if p_enemy == null:
		texture_rect.texture = null
		return
	var icon: Texture2D = p_enemy.icon
	if icon == null and p_enemy.body != null:
		icon = _peek_scene_texture(p_enemy.body)
	sprite_2d.texture = icon
	sprite_2d.position.y = p_enemy.position_y

# EnemyCard.icon 缺失时，从 body 场景里取一张预览贴图（不实例化）
func _peek_scene_texture(ps: PackedScene) -> Texture2D:
	var st = ps.get_state()
	if st == null:
		return null
	for n in st.get_node_count():
		for i in st.get_node_property_count(n):
			var v = st.get_node_property_value(n, i)
			if v is Texture2D:
				return v
	return null

func touch_out() -> void:
	_tooltip.dismiss()

func _preview_text(index: int = -1) -> void:
	GameEvents.emit_player_card_touch()
	on_touch = true
	_tooltip.preview("touch", index)

func _on_button_pressed():
	on_touch = false
	_tooltip.dismiss()
	SoundManager.play_sfx("ButtonSounds")
	if menu != null and enemy_card != null:
		menu.spawn_enemy(enemy_card)

func _on_button_gui_input(event: InputEvent):
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
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_button_pressed()

func _tooltip_content() -> Array:
	if enemy_card == null:
		return []
	# 说明允许有意留空（如 goliath/erosion_tower）：optional 段无译文时整段跳过。
	return [{"text": enemy_card.id + "_name", "role": "title"}, {"text": enemy_card.id + "_description", "optional": true}]
