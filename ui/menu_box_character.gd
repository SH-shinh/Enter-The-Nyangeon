extends MenuBox

@export var player_group: PlayerGroup

var character_group: Array[PlayerCard]

const character_card: PackedScene = preload("res://ui/menu_box_button.tscn")

func _ready() -> void:
	super._ready()
	add_character_button()

func add_character_button():
	if character_group.is_empty():
		for i in player_group.player_group:
			character_group.append(i)
	
	if !character_group.is_empty():
		for n in character_group:
			var ins := character_card.instantiate()
			ins.button_type = "character"
			ins.player_card = n
			button_box.add_child(ins)
			ins.update_button()
