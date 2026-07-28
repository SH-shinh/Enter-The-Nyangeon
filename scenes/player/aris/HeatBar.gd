extends Node2D

@export var over_heating: Node
@export var player: Node

@onready var bar = $TextureProgressBar

func _ready():
	over_heating.k_changed.connect(update_heat_bar)

func _physics_process(delta):
	self.position = player.gun.position

func update_heat_bar():
	bar.value = over_heating.k
	if bar.value > 0:
		self.visible = true
	else:
		self.visible = false
