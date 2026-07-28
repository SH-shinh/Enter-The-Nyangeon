extends Node2D

@onready var voodoo_doll_icon = preload("res://scenes/update_item/voodoo_doll_icon.tscn")

var group: Array = []
var num: int

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	PlayerData.bullet_damage_mult += 0.5
	PlayerData.hurt_mult_mult += 0.5
	PlayerData.update_player_ability()
	var sprite_2d = voodoo_doll_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "voodoo_doll":
		return
	if current_upgrade["voodoo_doll"]["quantity"] == 1:
		return
	num = current_upgrade["voodoo_doll"]["quantity"]
	PlayerData.bullet_damage_mult += 0.5
	PlayerData.hurt_mult_mult += 0.5
	PlayerData.update_player_ability()
