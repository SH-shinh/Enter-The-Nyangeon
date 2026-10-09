extends Control

@onready var score_box: VBoxContainer = $ScrollContainer/score_box
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var normal_sort: PanelContainer = $Node2D2/HBoxContainer/normal_sort
@onready var order_icon: TextureRect = $Node2D2/HBoxContainer/reverse_order/order_icon
@onready var character_sort: PanelContainer = $Node2D2/HBoxContainer/character_sort
@onready var menu_box_gamemode: PanelContainer = $Node2D2/HBoxContainer/menu_box_gamemode

@onready var clear_button: Button = $Node2D2/HBoxContainer/clear_button
@onready var clear_confirm: Control = $clear_confirm
@onready var clear_blocker: Button = $clear_confirm/blocker
@onready var clear_yes: Button = $clear_confirm/panel/HBoxContainer/yes
@onready var clear_no: Button = $clear_confirm/panel/HBoxContainer/no
@onready var clear_pop_anim: AnimationPlayer = $clear_confirm/AnimationPlayer

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

var _confirming: bool = false

func _ready() -> void:
	normal_sort.sort_changed.connect(get_normal_sort)
	character_sort.sort_changed.connect(get_character_filter)
	menu_box_gamemode.gamemode_changed.connect(get_gamemode_filter)
	clear_button.mouse_entered.connect(_on_clear_hover)
	clear_button.gui_input.connect(_on_clear_gui_input)
	clear_yes.mouse_entered.connect(_on_clear_hover)
	clear_no.mouse_entered.connect(_on_clear_hover)
	clear_yes.pressed.connect(_on_clear_yes)
	clear_no.pressed.connect(_on_clear_no)
	clear_blocker.pressed.connect(_on_clear_no)

func _unhandled_input(event:InputEvent ) -> void:
	if is_show == true:
		if event.is_action_pressed("pause"):
			if _confirming:
				_close_clear()
			else:
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
		clear_scoreboard()
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
	_force_close_clear()
	load_all_records()
	animation_player.play("enter_anim")
	is_show = true

func hide_scoreboard():
	if _confirming:
		_force_close_clear()
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
			ins.delete_confirmed.connect(_on_card_delete_confirmed)

func _on_card_delete_confirmed(record: Dictionary) -> void:
	if records == null:
		return
	for i in records.size():
		if is_same(records[i], record):
			records.remove_at(i)
			break
	Game.save_all_records_as_json("user://scorebound/game_score.json", records)
	scoreboard_filter()

func _is_button_press(event: InputEvent) -> bool:
	if event as InputEventScreenTouch and event.pressed:
		return true
	if event as InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		return true
	if event.is_action_pressed("ui_accept"):
		return true
	return false

func _on_reverse_order_gui_input(event: InputEvent) -> void:
	if _is_button_press(event):
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

func _on_clear_hover() -> void:
	SoundManager.play_sfx("ButtonSounds2")

func _on_clear_gui_input(event: InputEvent) -> void:
	if _is_button_press(event):
		clear_button.accept_event()
		_open_clear()

func _open_clear() -> void:
	_confirming = true
	clear_confirm.visible = true
	clear_pop_anim.play("pop_anim")

func _close_clear() -> void:
	_confirming = false
	clear_pop_anim.play_backwards("pop_anim")
	await clear_pop_anim.animation_finished
	clear_confirm.visible = false

func _force_close_clear() -> void:
	_confirming = false
	clear_pop_anim.stop()
	clear_confirm.visible = false

func _on_clear_yes() -> void:
	SoundManager.play_sfx("ButtonSounds")
	if records == null:
		records = []
	records.clear()
	sort_records = []
	Game.save_all_records_as_json("user://scorebound/game_score.json", records)
	clear_scoreboard()
	_close_clear()

func _on_clear_no() -> void:
	SoundManager.play_sfx("ButtonSounds")
	_close_clear()
