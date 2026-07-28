extends Control

@onready var score_box: VBoxContainer = $ScrollContainer/score_box
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var normal_sort: PanelContainer = $Node2D2/HBoxContainer/normal_sort
@onready var order_icon: TextureRect = $Node2D2/HBoxContainer/reverse_order/order_icon
@onready var character_sort: PanelContainer = $Node2D2/HBoxContainer/character_sort
@onready var menu_box_gamemode: PanelContainer = $Node2D2/HBoxContainer/menu_box_gamemode

const score_card_p: PackedScene = preload("res://ui/score_card.tscn")

var level_order = {
	"normal": 1,
	"hard": 2,
	"extreme": 3,
	"insane": 4,
}

var records: Array
var is_show: bool = false
var sort_records: Array
var reverse_order: bool = false
var now_normal_select: String = "date"
var now_character: String = "null"
var now_gamemode: Array[String]

func _ready() -> void:
	normal_sort.sort_changed.connect(get_normal_sort)
	character_sort.sort_changed.connect(get_character_filter)
	menu_box_gamemode.gamemode_changed.connect(get_gamemode_filter)

func _unhandled_input(event:InputEvent ) -> void:
	if is_show == true:
		if event.is_action_pressed("pause"):
			hide_scoreboard()

func date_to_number(date_dict: Dictionary) -> int:
	return date_dict["year"] * 1000000000000 + date_dict["month"] * 100000000 + date_dict["day"] * 1000000 + date_dict["hour"] * 10000 + date_dict["minute"] * 100 + date_dict["second"]

func get_normal_sort(select_name: String, _type_name: String):
	now_normal_select = select_name
	scoreboard_filter()

func scoreboard_normal_sort():
	if records.is_empty():
		return
	clear_scoreboard()
	if sort_records.is_empty():
		return
	
	if now_normal_select == "date":
		if reverse_order == false:
			sort_records.sort_custom(func(a, b): return date_to_number(a["date"]) > date_to_number(b["date"]))
		else:
			sort_records.sort_custom(func(a, b): return date_to_number(a["date"]) < date_to_number(b["date"]))
	elif now_normal_select == "level":
		if reverse_order == false:
			sort_records.sort_custom(func(a, b):
				return level_order[a["level"]] > level_order[b["level"]]
			)
		else:
			sort_records.sort_custom(func(a, b):
				return level_order[a["level"]] < level_order[b["level"]]
			)
	else:
		if reverse_order == false:
			sort_records.sort_custom(func(a, b): return a[now_normal_select] > b[now_normal_select])
		else:
			sort_records.sort_custom(func(a, b): return a[now_normal_select] < b[now_normal_select])
	add_score_card(sort_records)

func get_character_filter(character_name: String, _type_name: String):
	now_character = character_name
	scoreboard_filter()

func get_gamemode_filter(gamemode_group: Array, _type_name: String):
	now_gamemode = gamemode_group
	scoreboard_filter()

func scoreboard_filter():
	
	if records.is_empty():
		return
	
	if now_character != "null":
		sort_records = records.duplicate().filter(func (record):
			return record["player"] == now_character
		)
	else:
		sort_records = records.duplicate()
	
	if !now_gamemode.is_empty():
		for x in now_gamemode:
			sort_records = sort_records.filter(func (record):
				return record["game_mode"].has(x)
			)
	
	scoreboard_normal_sort()


func show_scoreboard():
	load_all_records()
	animation_player.play("enter_anim")
	is_show = true

func hide_scoreboard():
	is_show = false
	animation_player.play_backwards("enter_anim")
	await animation_player.animation_finished
	clear_scoreboard()

func clear_scoreboard():
	for n in score_box.get_children():
		n.queue_free()

func load_all_records():
	records = Game.load_all_records_as_json("user://scorebound/game_score.json")
	scoreboard_filter()

func add_score_card(now_records: Array):
	if !now_records.is_empty():
		for i in now_records:
			var ins := score_card_p.instantiate()
			score_box.add_child(ins)
			ins.record = i
			ins.load_record_data()

func _on_reverse_order_gui_input(event: InputEvent) -> void:
	if event as InputEventScreenTouch and event.pressed:
		_on_reverse_order_pressed()

func _on_reverse_order_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	if reverse_order == false:
		reverse_order = true
		order_icon.flip_v = false
		scoreboard_filter()
	else:
		reverse_order = false
		order_icon.flip_v = true
		scoreboard_filter()
