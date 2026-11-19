extends PanelContainer

signal selected
signal is_delay_end

var can_select: bool = true
var on_select: bool = false
var is_delay: bool = false
var look_at: float
var num: float

var on_touch: bool = false
var _touch_index: int = -1
var _touch_start: Vector2
var _touch_dragged: bool = false

# 稀有度配色统一取自 AbilityUpgrade.RARITY_COLORS
var color_group: Array = AbilityUpgrade.RARITY_COLORS

@onready var texture_rect: TextureRect = $%TextureRect
@onready var name_label: Label = $%NameLabel
@onready var description_label: Label = $%DescriptionLabel
@onready var node_2d_2 = $Node2D2
@onready var card_color = %CardColor
@onready var SSR = $Node2D3/CardColor/TextureRect
@onready var forward = $ContentScroll/VBoxContainer/Forward
@onready var negative = $ContentScroll/VBoxContainer/Negative
@onready var animation_player: AnimationPlayer = $AnimationPlayer

## 允许有意留空的 Label → 本地化键；语言切换时必须重算可见性。
var _optional_labels: Dictionary = {}

func _ready():
	gui_input.connect(on_gui_input)
	mouse_entered.connect(on_mouse_entered)
	mouse_exited.connect(on_mouse_exited)
	GameEvents.player_card_touch.connect(touch_out)

func _input(event: InputEvent) -> void:
	# 滚动容器可能消费拖动事件，提前观察，防止拖走再返回被当作确认。
	if event is InputEventScreenDrag and event.index == _touch_index:
		var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if _touch_start.distance_to(local_position) > 10.0:
			_touch_dragged = true
	elif event is InputEventScreenTouch and not event.pressed and event.index == _touch_index:
		_clear_touch.call_deferred(event.index)

func _clear_touch(index: int) -> void:
	if _touch_index == index:
		_touch_index = -1

func _process(_delta):
	if on_select == true:
		if on_touch == false:
			look_at = (get_global_mouse_position() - (self.global_position + Vector2(75,95))).normalized().angle() + PI/2
			num = (self.global_position + Vector2(75,95)).distance_to(get_global_mouse_position())
			if look_at > PI/2:
				look_at = -(look_at - PI)
			rotation = clamp(look_at * 0.0005 * num , -0.08, 0.08)
			node_2d_2.rotation = -rotation
		else:
			rotation = 0
			node_2d_2.rotation = 0
	

func play_card_in(delay: float = 0):
	modulate = Color.TRANSPARENT
	is_delay = true
	await get_tree().create_timer(delay).timeout
	is_delay = false
	is_delay_end.emit()
	$AnimationPlayer.play("card_in")

func set_ability_upgrade(upgrade:AbilityUpgrade):
	card_color.color = color_group[upgrade.rare]
	if upgrade.rare == 2:
		SSR.visible = true
	texture_rect.texture = upgrade.icon
	name_label.text = upgrade.id + "_name"
	_set_optional_label(description_label, upgrade.id + "_description")
	_set_optional_label(forward, upgrade.id + "_forward")
	_set_optional_label(negative, upgrade.id + "_negative")

## CSV 里留空的字段在 Godot 侧会回退成键名，只有拿到译文时才显示该行（隐藏即被 VBox 排除出布局）。
func _set_optional_label(label: Label, key: String) -> void:
	_optional_labels[label] = key
	label.text = key
	label.visible = not LocaleText.resolve(key).is_empty()

func _refresh_optional_labels() -> void:
	for entry in _optional_labels:
		if is_instance_valid(entry):
			(entry as Label).visible = not LocaleText.resolve(String(_optional_labels[entry])).is_empty()

func _notification(what: int) -> void:
	# set_locale 可能在 _ready 之前触发（同 docs/LEARNINGS.md 记的 credits 坑），必须守卫。
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not _optional_labels.is_empty():
		_refresh_optional_labels()

func on_gui_input(event: InputEvent):
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_touch_start = event.position
			_touch_dragged = false
		elif not event.pressed and event.index == _touch_index:
			var tapped: bool = not event.canceled and not _touch_dragged
			tapped = tapped and _touch_start.distance_to(event.position) <= 10.0
			tapped = tapped and Rect2(Vector2.ZERO, size).has_point(event.position)
			_touch_index = -1
			if tapped:
				button_pressed()
		return
	
	if event.is_action_pressed("shoot") and can_select == true and on_select == true:
		SoundManager.play_sfx("ButtonSounds")
		selected.emit()
		GameEvents.emit_on_selected()
		on_select = false
		$SelectCardAnim.play("selected")

func button_pressed():
	if on_touch == false:
		if can_select == true:
			
			GameEvents.emit_player_card_touch()
			await get_tree().create_timer(0.1).timeout
			on_touch = true
			
			SoundManager.play_sfx("ButtonSounds2")
			$SelectCardAnim.play("select_enter")
			await  get_tree().create_timer(0.1).timeout
			on_select = true
	else:
		if can_select == true and on_select == true:
			SoundManager.play_sfx("ButtonSounds")
			selected.emit()
			GameEvents.emit_on_selected()
			on_select = false
			$SelectCardAnim.play("selected")

func card_dis():
	$SelectCardAnim.play("discard")

func touch_out():
	
	await get_tree().create_timer(0.05).timeout
	
	if can_select == true and on_touch == true:
		on_touch = false
		$SelectCardAnim.play("select_exit")
		await  get_tree().create_timer(0.1).timeout
		on_select = false
		rotation = 0

func on_mouse_entered():
	if can_select == true:
		SoundManager.play_sfx("ButtonSounds2")
		$SelectCardAnim.play("select_enter")
		await  get_tree().create_timer(0.1).timeout
		on_select = true


func on_mouse_exited():
	if can_select == true:
		$SelectCardAnim.play("select_exit")
		await  get_tree().create_timer(0.1).timeout
		on_select = false
		rotation = 0
