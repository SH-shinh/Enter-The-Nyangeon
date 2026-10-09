extends MenuBox

@export var gamemode_group: Array[GameMode]
@onready var h_box_container: HBoxContainer = $HBoxContainer

const character_card: PackedScene = preload("res://ui/menu_box_button.tscn")

var button_group: Array

func _ready() -> void:
	super._ready()
	add_gamemode_button()
	gamemode_changed.connect(update_h_box)

func add_gamemode_button():
	# 本体（扫描 resources/game_mode）+ mod 模式，按 game_mode_id 去重
	var modes: Array[GameMode] = []
	var seen := {}
	for n in ModManager.get_base_game_modes():
		if n != null and not seen.has(n.game_mode_id):
			seen[n.game_mode_id] = true
			modes.append(n)
	for n in ModManager.get_content("game_modes"):
		if n != null and not seen.has(n.game_mode_id):
			seen[n.game_mode_id] = true
			modes.append(n)
	if modes.is_empty():
		modes = gamemode_group
	gamemode_group = modes
	if not gamemode_group.is_empty():
		for n in gamemode_group:
			var ins := character_card.instantiate()
			ins.button_type = "gamemode"
			ins.button_name = n.game_mode_id
			ins.toggle_mode = true
			button_box.add_child(ins)
			ins.update_button()
			button_group.append(ins)

func update_h_box(gamemodes: Array, _type_name: String):
	var children = h_box_container.get_children()
	if !children.is_empty():
		for n in children:
			n.queue_free()
	
	if !gamemodes.is_empty():
		for i in gamemodes:
			var ins := TextureRect.new()
			var icon: Texture
			for n in gamemode_group:
				if n.game_mode_id == i:
					icon = n.game_mode_icon
			ins.expand_mode = TextureRect.EXPAND_FIT_WIDTH
			ins.texture = icon
			h_box_container.add_child(ins)
	else:
		if !button_group.is_empty():
			for i in button_group:
				i.is_null_pressed()
