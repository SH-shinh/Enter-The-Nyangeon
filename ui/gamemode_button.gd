extends Node2D

@export var gamemode_card: Array[GameMode]

@onready var gamemode_type: PackedScene = preload("res://ui/gamemode_type.tscn")
@onready var grid_container: GridContainer = $MarginContainer/ScrollContainer/GridContainer

func _ready() -> void:
	add_gamemode_card()

func add_gamemode_card():
	if !gamemode_card.is_empty():
		for i in gamemode_card.size():
			var mode_card = gamemode_type.instantiate()
			mode_card.gamemode_card = gamemode_card[i]
			grid_container.add_child(mode_card)
			mode_card.get_gamemode_card()
