extends PanelContainer

@onready var texture_rect = $TextureRect
@onready var item_text_4: Label = %ItemText4
@onready var item_text = %ItemText
@onready var text_show = $Text
@onready var button: Button = $Button
@onready var sprite_2d = $TextureRect/Sprite2D

var menu: Node
var enemy_card: EnemyCard
var text_is_show: bool = false
var on_touch: bool = false

var touch_index: int = -1
var touch_start_position: Vector2 = Vector2.ZERO
const TAP_MAX_DISTANCE: float = 14.0

func _ready():
	GameEvents.player_card_touch.connect(touch_out)
	mouse_entered.connect(show_text)
	mouse_exited.connect(hide_text)

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
	item_text_4.text = p_enemy.id + "_name"
	item_text.text = p_enemy.id + "_description"


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

func _physics_process(_delta: float) -> void:
	if text_is_show == true:
		if on_touch == false:
			text_show.global_position = get_global_mouse_position()
		else:
			text_show.global_position = self.global_position

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

func _on_button_pressed():
	on_touch = false
	text_show.visible = false
	text_is_show = false
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
			if moved > TAP_MAX_DISTANCE:
				return
			if on_touch == false:
				_preview_text()
			else:
				_on_button_pressed()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_button_pressed()
