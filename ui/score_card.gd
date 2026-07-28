extends PanelContainer

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

const gamemode_card_p: PackedScene = preload("res://ui/gamemode_card.tscn")
const item_card_p: PackedScene = preload("res://ui/upgrade_item_card.tscn")

var record: Dictionary
var level: Level
var player_card: PlayerCard
var support_card: SupportCard

var gamemode_group: Array
var equip_group: Array

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
			var equip_data := load_resources("upgrades/" + i["upgrade_id"])
			var ins := item_card_p.instantiate()
			equip_box.add_child(ins)
			ins.set_up_item_card(equip_data)
			if i["quantity"] > 1:
				ins.item_quantity.text = str(i["quantity"])

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
		player_sprite.texture = player_card.sprite
		support_sprite.texture = support_card.character_sprite
		if record["is_win"] == true:
			player_sprite.frame = 0
			support_sprite.frame = 0
		else:
			player_sprite.frame = 3
			support_sprite.frame = 3
		player_name.text = player_card.id
		support_name.text = support_card.support_name2
		date.text = (str(record["date"]["year"])
			+ " " + str(record["date"]["month"])
			+ "/" + str(record["date"]["day"])
			+ " " + str(record["date"]["hour"])
			+ ":" + str(record["date"]["minute"])
			+ ":" + str(record["date"]["second"]))
		score_num.text = str(record["score"])
		round_num.text = str(record["round"])
		defeats_num.text = str(record["defeats"])
		coins_num.text = str(record["coins"])
		time_num.text = str(record["time"])
		
		load_all_gamemode()
		load_all_equip()
