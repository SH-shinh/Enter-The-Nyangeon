extends PanelContainer
class_name MenuBox

signal sort_changed(sort_name: String, type_name: String)
signal gamemode_changed(gamemodes: Array, type_name: String)

@export var self_type_name: String
@export var multi_select: bool = false

@onready var select_name: Label = $select_name
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var button_box: VBoxContainer = $Node2D/ScrollContainer/button_box

var multi_sort: Array[String]
var is_open: bool = false

func _ready() -> void:
	self.gui_input.connect(button_pressed)
	GameEvents.scoreboard_select.connect(menu_now_select)

func menu_now_select(button_select_name: String, type_name: String):
	if type_name == self_type_name:
		if multi_select == false:
			if self_type_name == "normal_sort":
				select_name.text = "button_" + button_select_name
			else:
				select_name.text = button_select_name
			sort_changed.emit(button_select_name, type_name)
		else:
			if button_select_name != "null":
				if !multi_sort.has(button_select_name):
					multi_sort.append(button_select_name)
				else:
					multi_sort.remove_at(multi_sort.find(button_select_name))
				if !multi_sort.is_empty():
					var sort_group: String
					for i in multi_sort:
						sort_group += i + " "
					select_name.text = sort_group
				else:
					select_name.text = "null"
			else:
				multi_sort.clear()
				select_name.text = "null"
			gamemode_changed.emit(multi_sort, type_name)

func button_pressed(event: InputEvent):
	if event as InputEventScreenTouch and event.pressed:
		SoundManager.play_sfx("ButtonSounds")
		if is_open == false:
			is_open = true
			open_menu_box()
		else:
			is_open = false
			close_menu_box()
	
	if event.is_action_pressed("shoot"):
		SoundManager.play_sfx("ButtonSounds")
		if is_open == false:
			is_open = true
			open_menu_box()
		else:
			is_open = false
			close_menu_box()

func open_menu_box():
	animation_player.play("box_open")

func close_menu_box():
	animation_player.play_backwards("box_open")
