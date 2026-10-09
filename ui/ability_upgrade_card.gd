extends PanelContainer

signal selected
signal is_delay_end

var can_select: bool = true
var on_select: bool = false
var is_delay: bool = false
var look_at: float
var num: float

var on_touch: bool = false

# 稀有度配色统一取自 AbilityUpgrade.RARITY_COLORS
var color_group: Array = AbilityUpgrade.RARITY_COLORS

@onready var texture_rect: TextureRect = $%TextureRect
@onready var name_label: Label = $%NameLabel
@onready var description_label: Label = $%DescriptionLabel
@onready var node_2d_2 = $Node2D2
@onready var card_color = %CardColor
@onready var SSR = $Node2D3/CardColor/TextureRect
@onready var forward = $VBoxContainer/Forward
@onready var negative = $VBoxContainer/Negative
@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready():
	gui_input.connect(on_gui_input)
	mouse_entered.connect(on_mouse_entered)
	mouse_exited.connect(on_mouse_exited)
	GameEvents.player_card_touch.connect(touch_out)

func _auto_text():
	if name_label.size.x > 124:
		var now_font = name_label.get("theme_override_font_sizes/font_size")
		if now_font > 1:
			now_font -= 1
			name_label.set("theme_override_font_sizes/font_size", now_font)
	
	if self.size.y > 253:
		var new_font = description_label.get("theme_override_font_sizes/font_size")
		if new_font > 1:
			new_font -= 1
			description_label.set("theme_override_font_sizes/font_size", new_font)
			forward.set("theme_override_font_sizes/font_size", new_font)
			negative.set("theme_override_font_sizes/font_size", new_font)

func _process(_delta):
	if on_select == true:
		if on_touch == false:
			look_at = (get_global_mouse_position() - (self.global_position + Vector2(75,95))).normalized().angle() + PI/2
			num = (self.global_position + Vector2(75,95)).distance_to(get_global_mouse_position())
			if look_at > PI/2:
				look_at = -(look_at - PI)
			rotation = clamp(-0.08, look_at * 0.0005 * num , 0.08)
			node_2d_2.rotation = -rotation
		else:
			rotation = 0
			node_2d_2.rotation = 0
	
	_auto_text()

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
	description_label.text = upgrade.id + "_description"
	forward.text = upgrade.id + "_forward"
	negative.text = upgrade.id+ "_negative"

func on_gui_input(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		button_pressed()
	
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
