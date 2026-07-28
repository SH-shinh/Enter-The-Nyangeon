extends Node2D
@onready var boom: PackedScene = preload("res://script/explosion.tscn")

func _ready():
	GameEvents.enemy_hit_position.connect(boom_shoot)

func boom_shoot(hit_body: Node):
	if randf_range(0, 100) < 200:
		var root = get_tree().get_first_node_in_group("SELayer")
		var a = boom.instantiate()
		a.global_position = hit_body.global_position
		root.add_child(a)
