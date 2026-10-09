extends PanelContainer

signal delete_confirmed(record: Dictionary)

@onready var level_color: ColorRect = %level_color
@onready var player_sprite: Sprite2D = %player_sprite
@onready var player_name: Label = %PlayerName
@onready var date: Label = %Date
@onready var support_sprite: Sprite2D = %support_sprite
@onready var support_name: Label = %SupportName
@onready var score_num: Label = %ScoreNum
@onready var level_name: Label = %LevelName
@onready var player_id: Label = %player_id
@onready var round_num: Label = %RoundNum
@onready var defeats_num: Label = %DefeatsNum
@onready var coins_num: Label = %CoinsNum
@onready var time_num: Label = %TimeNum
@onready var gamemode_box: HBoxContainer = %gamemode_box
@onready var equip_box: GridContainer = %equip_box

@onready var delete_button: PanelContainer = $Node2D/delete_button
@onready var sure_button: PanelContainer = $Node2D/sure_button
@onready var del_anim: AnimationPlayer = $Node2D/AnimationPlayer
@onready var sure_anim: AnimationPlayer = $Node2D/AnimationPlayer2
@onready var yes: Button = $Node2D/sure_button/HBoxContainer/yes
@onready var no: Button = $Node2D/sure_button/HBoxContainer/no

const gamemode_card_p: PackedScene = preload("res://ui/gamemode_card.tscn")
const item_card_p: PackedScene = preload("res://ui/upgrade_item_card.tscn")

var record: Dictionary
var level: Level
var player_card: PlayerCard
var support_card: SupportCard

var gamemode_group: Array
var equip_group: Array

var _confirming: bool = false

func _ready() -> void:
	delete_button.mouse_entered.connect(_on_delete_hover_in)
	delete_button.mouse_exited.connect(_on_delete_hover_out)
	delete_button.gui_input.connect(_on_delete_gui_input)
	yes.mouse_entered.connect(_on_confirm_hover)
	no.mouse_entered.connect(_on_confirm_hover)
	yes.pressed.connect(_on_yes_pressed)
	no.pressed.connect(_on_no_pressed)

func _is_button_press(event: InputEvent) -> bool:
	if event as InputEventScreenTouch and event.pressed:
		return true
	if event as InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		return true
	if event.is_action_pressed("ui_accept"):
		return true
	return false

func _on_delete_hover_in() -> void:
	if _confirming:
		return
	SoundManager.play_sfx("ButtonSounds2")
	del_anim.play("hover_anim")

func _on_delete_hover_out() -> void:
	if _confirming:
		return
	del_anim.play_backwards("hover_anim")

func _on_delete_gui_input(event: InputEvent) -> void:
	if _confirming:
		return
	if _is_button_press(event):
		delete_button.accept_event()
		_confirming = true
		SoundManager.play_sfx("ButtonSounds")
		del_anim.play("press_anim")
		sure_anim.play("sure_anim")

func _on_confirm_hover() -> void:
	SoundManager.play_sfx("ButtonSounds2")

func _on_yes_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	delete_confirmed.emit(record)

func _on_no_pressed() -> void:
	SoundManager.play_sfx("ButtonSounds")
	_confirming = false
	sure_anim.play_backwards("sure_anim")
	del_anim.play_backwards("hover_anim")

func load_resources(path: String) -> Resource:
	var load_resource := load("res://resources/" + path + ".tres")
	return load_resource

func load_all_gamemode():
	if !record["game_mode"].is_empty():
		for i in record["game_mode"]:
			gamemode_group.append(load_resources("game_mode/" + i + "_mode"))
		
		for n in gamemode_group:
			var ins := gamemode_card_p.instantiate()
			gamemode_box.add_child(ins)
			ins.set_gamemode_card(n)

func load_all_equip():
	equip_group = record["equip"].values()
	if !equip_group.is_empty():
		for i in equip_group:
			var equip_data = ModManager.get_resource("upgrades", str(i["upgrade_id"]))
			if equip_data == null:
				equip_data = load_resources("upgrades/" + i["upgrade_id"])
			var ins := item_card_p.instantiate()
			equip_box.add_child(ins)
			ins.set_up_item_card(equip_data)
			if i["quantity"] > 1:
				ins.item_quantity.text = str(int(i["quantity"]))

func load_record_data():
	if !record.is_empty():
		level = load_resources("level/" + record["level"])
		player_card = load_resources("player/" + record["player"])
		if record["support"] == null or record["support"] == "null":
			support_card = load_resources("support/" + "null_support")
		else:
			support_card = load_resources("support/" + record["support"])
		
		level_name.text = level.level_name
		level_name.set("theme_override_colors/font_color", level.level_name_color)
		level_color.color = level.level_color
		player_id.text = record["player_id"]
		player_sprite.texture = LazyTexture.load_uncached(player_card.sprite_path)
		support_sprite.texture = LazyTexture.load_uncached(support_card.character_sprite_path)
		if record["is_win"] == true:
			player_sprite.frame = 0
			support_sprite.frame = 0
		else:
			player_sprite.frame = 3
			support_sprite.frame = 3
		player_name.text = player_card.id
		support_name.text = support_card.support_name2
		date.text = (str(int(record["date"]["year"]))
			+ " " + str(int(record["date"]["month"]))
			+ "/" + str(int(record["date"]["day"]))
			+ " " + str(int(record["date"]["hour"]))
			+ ":" + str(int(record["date"]["minute"]))
			+ ":" + str(int(record["date"]["second"])))
		score_num.text = str(int(record["score"]))
		round_num.text = str(int(record["round"]))
		defeats_num.text = str(int(record["defeats"]))
		coins_num.text = str(int(record["coins"]))
		time_num.text = str(record["time"])
		
		load_all_gamemode()
		load_all_equip()
