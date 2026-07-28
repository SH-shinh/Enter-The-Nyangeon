extends Node2D

var player: Node
var num: int

var equip_luck: int = 10
var equip_cd: int = 0
var can_shoot: bool = true

var launcher: Node

@onready var bullet_launcher: PackedScene = preload("res://scenes/update_item/player_bullet_launcher.tscn")

func _ready():
	first_activation()
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.player_bullet_hit_enemy.connect(shoot_bullet)
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.global_time_count.connect(time_count)

func time_count():
	if equip_cd > 0:
		equip_cd -= 1
		if equip_cd <= 0:
			can_shoot = true

func first_activation():
	
	var ins = bullet_launcher.instantiate()
	ins.shoot_at_once = false
	ins.end_free = false
	get_tree().get_first_node_in_group("EquipLayer").add_child(ins)
	launcher = ins
	
	equip_luck = 10
	PlayerData.update_player_ability()

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "shrapnel_bullet":
		return
	if current_upgrade["shrapnel_bullet"]["quantity"] == 1:
		return
	num = current_upgrade["shrapnel_bullet"]["quantity"]
	equip_luck += 10
	PlayerData.update_player_ability()

func shoot_bullet(bullet_body: Node):
	if can_shoot == true:
		
		var luck = randf_range(0, 200)
		if luck < (player.stats.luck + equip_luck):
			can_shoot = false
			launcher.rotation = bullet_body.rotation
			launcher.bullet = player.gun.bullet
			launcher.pool_id = player.gun.bullet_pool_id
			launcher.bullet_count = 4
			launcher.bullet_arc = 270
			launcher.bullet_speed = player.stats.bullet_speed
			launcher.bullet_penetrate = player.stats.bullet_penetrate + 1
			launcher.collision_num = player.stats.collision_num
			launcher.global_position = bullet_body.global_position
			launcher.shoot_bullet.call_deferred()
			equip_cd = 1
