extends Node2D

var shiroko_drone: Node
var num: int

@onready var shiroko_drone_body: PackedScene = preload("res://scenes/update_item/shiroko_drone_body.tscn")


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	var body = shiroko_drone_body.instantiate()
	get_tree().get_first_node_in_group("EquipLayer").add_child(body)
	body.global_position = self.global_position
	PlayerData.update_player_ability()

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "shiroko_drone":
		return
	if current_upgrade["shiroko_drone"]["quantity"] == 1:
		return
	num = current_upgrade["shiroko_drone"]["quantity"]
	shiroko_drone = get_tree().get_first_node_in_group("ShirokoDrone")
	shiroko_drone.shiroko_drone_damage_add += 20
	shiroko_drone.shoot_cd_timer_mult *= 0.8
	PlayerData.update_player_ability()
