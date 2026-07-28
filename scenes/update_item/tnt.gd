extends Node2D

var num: int
var player: Node
var group: Array = []
@onready var tnt_icon = preload("res://scenes/update_item/tnt_icon.tscn")

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.explosion_damage.connect(explosion_knockback)

func first_activation():
	PlayerData.explosion_damage_mult += 0.55
	PlayerData.explosion_range_mult += 0.35
	PlayerData.update_player_ability()
	var sprite_2d = tnt_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "tnt":
		return
	if current_upgrade["tnt"]["quantity"] == 1:
		return
	num = current_upgrade["tnt"]["quantity"]

func explosion_knockback(explosion_position: Vector2, explosion_range: float):
	if explosion_position.distance_to(player.global_position) < explosion_range:
		player.hurt_dir = (player.global_position - explosion_position ).normalized()
		player.hurt_knockback = player.stats.bullet_knockback + 200
		player.is_hurt.emit()
