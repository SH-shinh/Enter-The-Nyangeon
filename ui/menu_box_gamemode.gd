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
	if !gamemode_group.is_empty():
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
