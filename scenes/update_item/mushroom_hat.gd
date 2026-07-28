extends Node2D

@onready var mushroom_hat_icon = preload("res://scenes/update_item/mushroom_hat_icon.tscn")

var rail_group: Array
var num: int

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.bullet_damage_mult += 0.25
	PlayerData.bullet_scale_mult += 2
	PlayerData.bullet_kill_time_mult *= 0.06
	PlayerData.bullet_speed_mult *= 0.6
	PlayerData.bullet_recoil_mult += 0.3
	PlayerData.update_player_ability()
	var sprite_2d = mushroom_hat_icon.instantiate()
	rail_group = get_tree().get_nodes_in_group("Hat")
	for i in rail_group:
		if i.hat_use == false:
			i.add_child(sprite_2d)
			i.hat_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "mushroom_hat":
		return
	if current_upgrade["mushroom_hat"]["quantity"] == 1:
		return
	num = current_upgrade["mushroom_hat"]["quantity"]
	PlayerData.bullet_damage_mult += 0.25
	PlayerData.bullet_kill_time_mult *= 0.9
	PlayerData.update_player_ability()
