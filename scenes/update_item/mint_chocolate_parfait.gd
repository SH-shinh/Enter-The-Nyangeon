extends Node2D

@onready var fly_damage = preload("res://scenes/player_buff/fly_damage_bullet.tscn")
@onready var mint_chocolate_parfait_icon = preload("res://scenes/update_item/mint_chocolate_parfait_icon.tscn")

var num: int
var group: Array = []

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.player_shot_position.connect(fly_damage_bullet_add)

func first_activation():
	var sprite_2d = mint_chocolate_parfait_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "mint_chocolate_parfait":
		return
	if current_upgrade["mint_chocolate_parfait"]["quantity"] == 1:
		return
	num = current_upgrade["mint_chocolate_parfait"]["quantity"]

func fly_damage_bullet_add(shot_position: Vector2, bullet_body: Node):
	
	var ins = fly_damage.instantiate()
	bullet_body.call_deferred("add_child", ins)
