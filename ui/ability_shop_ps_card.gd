extends PanelContainer

@export var is_test: bool = false

@onready var cost = $Node2D/upgrade/Node2D/ColorRect/Coin
@onready var weapon_icon = $Node2D/RareColor/Weapon_icon
@onready var t_num_l = $Node2D/RareColor/TNumL
@onready var rare_color_c = $Node2D/RareColor
@onready var text_follow = $Node2D2
@onready var marker_2d = $Marker2D
@onready var upgrade = $Node2D/upgrade
@onready var smoke = preload("res://scenes/bullet/spread_smoke.tscn")

@onready var t_0 = $Node2D2/PanelContainer/VBoxContainer/t0
@onready var t_1 = $Node2D2/PanelContainer/VBoxContainer/t1
@onready var t_2 = $Node2D2/PanelContainer/VBoxContainer/t2
@onready var t_3 = $Node2D2/PanelContainer/VBoxContainer/t3


var t_num: int = 0
var icon_num: int = 0
var coin_cost:int = 0

var on_touch: bool = false
var touch_position: Vector2

var player: Node

var on_text_follow: bool = false

var rare_color: Array[Color] =[ Color(0.779, 0.795, 0.81), Color(0.464, 0.673, 0.832), Color(0.884, 0.764, 0.435), Color(0.985, 0.643, 0.909) ]


func _ready():
	upgrade.mouse_entered.connect(mouse_in)
	upgrade.mouse_exited.connect(mouse_out)
	upgrade.gui_input.connect(mouse_selected)
	GameEvents.get_player.connect(get_player)
	GameEvents.player_card_touch.connect(touch_out)
	cost_count()

func get_player():
	player = get_tree().get_first_node_in_group("Player")
	reset_data()

func reset_data():
	t_num = 0
	icon_num = 0
	coin_cost = 0
	cost_count()
	item_text_get()
	t_num_l.text = "T" + str(t_num)
	reset_font_color()

func _process(_delta):
	if on_text_follow == true:
		if on_touch == false:
			text_follow.global_position = get_global_mouse_position()
		else:
			text_follow.position = Vector2(0, -20)


func mouse_in():
	SoundManager.play_sfx("ButtonSounds2")
	$Node2D/upgrade/AnimationPlayer.play("mouse_in")
	$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("hammer_anim")
	on_text_follow = true
	text_follow.visible = true

func mouse_out():
	$Node2D/upgrade/AnimationPlayer.play("mouse_out")
	$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("RESET")
	on_text_follow = false
	text_follow.visible = false

func touch_out():
	await get_tree().create_timer(0.05).timeout
	
	if on_touch == true:
		on_touch = false
		$Node2D/upgrade/AnimationPlayer.play("mouse_out")
		$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("RESET")
		on_text_follow = false
		text_follow.visible = false

func touch_button():
	if on_touch == false:
		GameEvents.emit_player_card_touch()
		await get_tree().create_timer(0.1).timeout
		on_touch = true
		SoundManager.play_sfx("ButtonSounds2")
		$Node2D/upgrade/AnimationPlayer.play("mouse_in")
		$Node2D/upgrade/Node2D/ColorRect/AnimationPlayer.play("hammer_anim")
		on_text_follow = true
		text_follow.visible = true
		
	else:
		
		if t_num >= 3:
			$Node2D/upgrade/AnimationPlayer.play("coin_lack")
			return
		
		if player.stats.usable_coin < coin_cost:
			$Node2D/upgrade/AnimationPlayer.play("coin_lack")
		else:
			SoundManager.play_sfx("ButtonSounds")
			GameEvents.emit_player_coins_cost(coin_cost)
			item_upgrade()
			GameEvents.emit_player_ps_upgrade(t_num)

func mouse_selected(event: InputEvent):
	
	
	if event as InputEventScreenTouch and event.pressed:
		touch_button()
	
	if event.is_action_pressed("shoot"):
		
		if t_num >= 3:
			$Node2D/upgrade/AnimationPlayer.play("coin_lack")
			return
		
		if player.stats.usable_coin < coin_cost:
			$Node2D/upgrade/AnimationPlayer.play("coin_lack")
		else:
			SoundManager.play_sfx("ButtonSounds")
			GameEvents.emit_player_coins_cost(coin_cost)
			item_upgrade()
			GameEvents.emit_player_ps_upgrade(t_num)


func cost_count():
	if is_test == false:
		if t_num == 0:
			coin_cost = 150
		elif t_num == 1:
			coin_cost = 800
		elif t_num == 2:
			coin_cost = 2000
		
		cost.text = str(coin_cost)
	else:
		coin_cost = 0
		cost.text = "FREE"

func reset_font_color():
	t_0.set("theme_override_colors/font_color", Color(1,1,1))
	t_1.set("theme_override_colors/font_color", Color(0.569,0.569,0.569))
	t_2.set("theme_override_colors/font_color", Color(0.569,0.569,0.569))
	t_3.set("theme_override_colors/font_color", Color(0.569,0.569,0.569))

func item_text_get():
	
	weapon_icon.texture = player.ps_card.weapon_icon
	var _text_1: String = ""
	
	if t_num == 0:
		rare_color_c.color = rare_color[0]
		t_0.set("theme_override_colors/font_color", Color(1,1,1))
	elif t_num == 1:
		rare_color_c.color = rare_color[1]
		t_1.set("theme_override_colors/font_color", Color(1,1,1))
	elif t_num == 2:
		rare_color_c.color = rare_color[2]
		t_2.set("theme_override_colors/font_color", Color(1,1,1))
	else:
		rare_color_c.color = rare_color[3]
		t_3.set("theme_override_colors/font_color", Color(1,1,1))
	
	var pc = player.player_card if player != null else null
	t_0.text = _ps_text(pc, 0)
	t_1.text = _ps_text(pc, 1)
	t_2.text = _ps_text(pc, 2)
	t_3.text = _ps_text(pc, 3)


# 本地化缺失时回退到角色描述，避免显示原始键（如 xxx_ps_1）
func _ps_text(card, idx: int) -> String:
	if card == null:
		return ""
	var key: String = str(card.id) + "_ps_" + str(idx)
	var t := tr(key)
	return t if t != key else str(card.description)

func smoke_anim():
	var ins = smoke.instantiate()
	ins.position = marker_2d.position
	add_child(ins)

func item_upgrade():
	
	if t_num >= 3:
		return
	
	t_num += 1
	cost_count()
	item_text_get()
	smoke_anim()
	t_num_l.text = "T" + str(t_num)
	if t_num >= 3:
		cost.text = "MAX"
