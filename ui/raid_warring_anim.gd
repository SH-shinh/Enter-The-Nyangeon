extends Node2D

@export var map_position: String
@onready var target = $Target

func _ready():
	if map_position == "N":
		GameEvents.map_n_warring.connect(warring_anim)
	if map_position == "E":
		GameEvents.map_e_warring.connect(warring_anim)
	if map_position == "S":
		GameEvents.map_s_warring.connect(warring_anim)
	if map_position == "W":
		GameEvents.map_w_warring.connect(warring_anim)

func warring_anim():
	self.visible = true
	await get_tree().create_timer(4.0).timeout
	self.visible = false
