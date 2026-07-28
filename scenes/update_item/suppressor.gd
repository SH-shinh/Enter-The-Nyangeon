extends Node2D

@onready var Suppressor: PackedScene = preload("res://scenes/update_item/suppressor_icon.tscn")
var num: int
var muzzle_group: Array

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.bullet_damage_mult += 0.15
	PlayerData.bullet_knockback_mult -= 0.1
	PlayerData.bullet_recoil_mult -= 0.1
	PlayerData.update_player_ability()
	var player = get_tree().get_first_node_in_group("Player")
	player.gun.fire_sounds.pitch_scale *= 0.7
	
	var sprite_2d = Suppressor.instantiate()
	muzzle_group = get_tree().get_nodes_in_group("Muzzle")
	for i in muzzle_group:
		if i.muzzle_use == false:
			i.add_child(sprite_2d)
			i.muzzle_use = true
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "suppressor":
		return
	if current_upgrade["suppressor"]["quantity"] == 1:
		return
	num = current_upgrade["suppressor"]["quantity"]
	PlayerData.bullet_damage_mult += 0.15
	PlayerData.bullet_knockback_mult -= 0.1
	PlayerData.update_player_ability()
