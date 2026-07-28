extends Node2D

@onready var yokai_max_icon: PackedScene = preload("res://scenes/update_item/yokai_max_icon.tscn")

var group: Array
var num: int


func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.MAX_SPEED_mult += 0.2
	PlayerData.bullet_speed_mult += 0.4
	PlayerData.bullet_shoot_time_mult += 0.2
	PlayerData.update_player_ability()
	var sprite_2d = yokai_max_icon.instantiate()
	group = get_tree().get_nodes_in_group("Hat")
	for i in group:
		if i.hat_use == false:
			i.add_child(sprite_2d)
			i.hat_use = true
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "yokai_max":
		return
	if current_upgrade["yokai_max"]["quantity"] == 1:
		return
	num = current_upgrade["yokai_max"]["quantity"]
	PlayerData.bullet_shoot_time_mult += 0.2
	PlayerData.update_player_ability()
