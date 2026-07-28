extends Node2D

@onready var blunderbuss_muzzle: PackedScene = preload("res://scenes/update_item/blunderbuss_muzzle_icon.tscn")
@onready var shoot_fire: PackedScene = preload("res://scenes/bullet/shoot_fire_1.tscn")
@onready var fire_damage: PackedScene = preload("res://script/fire_damage.tscn")
var num: int
var group: Array
var player: Node
var fire_num: int = 1

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.player_gun_shoot.connect(add_shoot_fire)

func first_activation():
	fire_num = 1
	PlayerData.critical_damage_add += 1
	PlayerData.bullet_recoil_mult += 1
	PlayerData.bullet_speed_mult += 0.5
	PlayerData.update_player_ability()
	
	player.gun.fire_sounds.pitch_scale *= 1.2
	var sprite_2d = blunderbuss_muzzle.instantiate()
	group = get_tree().get_nodes_in_group("Muzzle")
	for i in group:
		if i.muzzle_use == false:
			i.add_child(sprite_2d)
			i.muzzle_use = true
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "blunderbuss_muzzle":
		return
	if current_upgrade["blunderbuss_muzzle"]["quantity"] == 1:
		return
	num = current_upgrade["blunderbuss_muzzle"]["quantity"]
	fire_num += 1
	PlayerData.update_player_ability()

func add_shoot_fire(gun: Node):
	var fire_ins = shoot_fire.instantiate()
	var damage_ins = fire_damage.instantiate()
	fire_ins.position = gun.shoot_position.global_position
	fire_ins.rotation = gun.global_rotation
	damage_ins.position = gun.shoot_position.global_position
	damage_ins.rotation = gun.global_rotation
	damage_ins.fire_damage = 5 * player.stats.dot_damage
	damage_ins.damage_knockback = 150 + player.stats.bullet_knockback
	damage_ins.fire_num = fire_num
	get_tree().get_first_node_in_group("SELayer").add_child(fire_ins)
	get_tree().get_first_node_in_group("BulletRoot").add_child(damage_ins)
