extends Node2D

@onready var mushroom_hat_icon = preload("res://scenes/update_item/arale_hat_icon.tscn")

var rail_group: Array =[]
var num: int

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.MAX_SPEED_mult += 0.5
	PlayerData.knockback_resis_add += 80
	PlayerData.hurt_mult_mult += 0.2
	PlayerData.update_player_ability()
	var sprite_2d = mushroom_hat_icon.instantiate()
	rail_group = get_tree().get_nodes_in_group("Hat")
	for i in rail_group:
		if i.hat_use == false:
			i.add_child(sprite_2d)
			i.hat_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "arale_hat":
		return
	if current_upgrade["arale_hat"]["quantity"] == 1:
		return
	num = current_upgrade["arale_hat"]["quantity"]
	PlayerData.MAX_SPEED_mult += 0.5
	PlayerData.hurt_mult_mult += 0.2
	PlayerData.update_player_ability()
