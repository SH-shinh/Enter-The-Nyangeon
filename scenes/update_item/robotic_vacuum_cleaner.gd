extends Node2D

var robotic_vacuum_cleaner: Node
var num: int

@onready var robotic_vacuum_cleaner_body: PackedScene = preload("res://scenes/update_item/robotic_vacuum_cleaner_body.tscn")


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	var body = robotic_vacuum_cleaner_body.instantiate()
	get_tree().get_first_node_in_group("PlayerRoot").add_child(body)
	body.global_position = self.global_position
	PlayerData.update_player_ability()

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "robotic_vacuum_cleaner":
		return
	if current_upgrade["robotic_vacuum_cleaner"]["quantity"] == 1:
		return
	num = current_upgrade["robotic_vacuum_cleaner"]["quantity"]
	robotic_vacuum_cleaner = get_tree().get_first_node_in_group("RoboticCleaner")
	robotic_vacuum_cleaner.equip_speed += 50
	PlayerData.update_player_ability()
