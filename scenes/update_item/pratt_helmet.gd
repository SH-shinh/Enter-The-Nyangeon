extends Node2D

@onready var pratt_helmet_icon = preload("res://scenes/update_item/pratt_helmet_icon.tscn")
@onready var player_bullet_launcher = $PlayerBulletLauncher

var group: Array =[]
var num: int
var player: Node
var shoot_num: int = 7
var bullet_num: int = 2
var is_stop: bool = false

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.player_shot_position.connect(shoot_count)
	

func first_activation():
	bullet_num = 2
	shoot_num = 7
	PlayerData.update_player_ability()
	var sprite_2d = pratt_helmet_icon.instantiate()
	group = get_tree().get_nodes_in_group("Hat")
	for i in group:
		if i.hat_use == false:
			i.add_child(sprite_2d)
			i.hat_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "pratt_helmet":
		return
	if current_upgrade["pratt_helmet"]["quantity"] == 1:
		return
	num = current_upgrade["pratt_helmet"]["quantity"]
	bullet_num += 1
	PlayerData.update_player_ability()

func shoot_count(shot_position: Vector2, bullet_body: Node):
	if is_stop == true:
		return
	shoot_num -= 1
	if shoot_num == 0:
		is_stop = true
		player_bullet_launcher.rotation = bullet_body.rotation
		shoot_num = 7 + bullet_num
		shoot_bullet()

func shoot_bullet():
	player_bullet_launcher.bullet = player.gun.bullet
	player_bullet_launcher.pool_id = player.gun.bullet_pool_id
	player_bullet_launcher.bullet_count = bullet_num
	player_bullet_launcher.bullet_arc = 90 + player.stats.bullet_arc
	player_bullet_launcher.bullet_speed = player.stats.bullet_speed
	player_bullet_launcher.bullet_penetrate = player.stats.bullet_penetrate
	player_bullet_launcher.collision_num = player.stats.collision_num
	player_bullet_launcher.shoot_bullet.call_deferred()
	is_stop = false
