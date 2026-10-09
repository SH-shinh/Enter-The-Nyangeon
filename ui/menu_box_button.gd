extends PanelContainer

@export var button_name: String
@export var button_type: String
@export var toggle_mode: bool

@onready var color_rect: ColorRect = $ColorRect
@onready var button_name_label: Label = $button_name
@onready var sprite_2d: Sprite2D = $ColorRect/Sprite2D

var isDrag: bool = false
var start_pos: float = 0
var player_card: PlayerCard


var is_selected: bool = false
var _revealed_path: String = ""

func _ready() -> void:
	self.gui_input.connect(button_pressed)
	self.mouse_entered.connect(mouse_in)
	self.mouse_exited.connect(mouse_out)
	update_button()

func update_button():
	if button_type == "normal_sort":
		button_name_label.text = "button_" + button_name
		sprite_2d.texture = null
	elif button_type == "character":
		if player_card != null:
			button_name = player_card.id
			button_name_label.text = player_card.id
		else:
			button_name_label.text = button_name
		sprite_2d.texture = null
	elif button_type == "gamemode":
		if button_name != "null":
			button_name_label.text = button_name + "_id"
		else:
			button_name_label.text = button_name
		sprite_2d.texture = null

# 角色立绘按需加载/释放（列表可见性由 menu_box_character 调用）；幂等
func reveal() -> void:
	if button_type != "character" or player_card == null:
		return
	var p := player_card.sprite_path
	if _revealed_path == p and sprite_2d.texture != null:
		return
	if _revealed_path != "":
		LazyTexture.release(_revealed_path)
	sprite_2d.texture = LazyTexture.acquire(p)
	_revealed_path = p


func conceal() -> void:
	if _revealed_path != "":
		LazyTexture.release(_revealed_path)
		_revealed_path = ""
	sprite_2d.texture = null


func _exit_tree() -> void:
	if _revealed_path != "":
		LazyTexture.release(_revealed_path)
		_revealed_path = ""


func is_pressed():
	if toggle_mode == true:
		if is_selected == false:
			is_selected = true
			color_rect.color = Color(0.6,0.6,0.6)
		else:
			is_selected = false
			color_rect.color = Color(0.141,0.141,0.141)
	SoundManager.play_sfx("ButtonSounds")
	GameEvents.emit_scoreboard_select(button_name, button_type)

func is_null_pressed():
	is_selected = false
	color_rect.color = Color(0.141,0.141,0.141)

func button_pressed(event: InputEvent):
	
	if event as InputEventScreenTouch and event.pressed:
		isDrag = true
		start_pos = event.position.y
	
	if event as InputEventScreenTouch and !event.pressed:
		isDrag = false
		var offset = event.position.y - start_pos
		if offset <= 10:
			is_pressed()
		start_pos = 0
	
	if event.is_action_pressed("shoot"):
		is_pressed()

func mouse_in():
	SoundManager.play_sfx("ButtonSounds2")
	if is_selected == false:
		color_rect.color = Color(0.141,0.141,0.141)

func mouse_out():
	if is_selected == false:
		color_rect.color = Color(0.094,0.094,0.094)
