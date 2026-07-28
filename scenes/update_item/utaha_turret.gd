extends Node2D

@onready var turret = preload("res://scenes/update_item/utaha_turret_body.tscn")

var num: int

var spawn_point: Vector2 = Vector2(704, 448)

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	add_turret()
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "utaha_turret":
		return
	if current_upgrade["utaha_turret"]["quantity"] == 1:
		return
	num = current_upgrade["utaha_turret"]["quantity"]
	add_turret()


func add_turret():
	var turret_position = spawn_point + Vector2( randf_range(-80,80), randf_range(-50,50)  )
	var ins = turret.instantiate()
	ins.global_position = turret_position
	get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)
	
