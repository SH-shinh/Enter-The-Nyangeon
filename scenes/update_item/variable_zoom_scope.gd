extends Node2D

@export var pool_id: String = "hit_flash"

@onready var variable_zoom_scope_icon: PackedScene = preload("res://scenes/update_item/variable_zoom_scope_icon.tscn")
@onready var hit_flash: PackedScene = preload("res://scenes/bullet/hit_flash.tscn")

var rail_group: Array
var num: int
var penetrate_num: int = 1

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.player_bullet_kill_enemy.connect(bullet_add_penetrate)

func first_activation():
	penetrate_num = 1
	PlayerData.update_player_ability()
	var sprite_2d = variable_zoom_scope_icon.instantiate()
	rail_group = get_tree().get_nodes_in_group("Rail")
	for i in rail_group:
		if i.picatinny_rail_use == false:
			i.add_child(sprite_2d)
			i.picatinny_rail_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "variable_zoom_scope":
		return
	if current_upgrade["variable_zoom_scope"]["quantity"] == 1:
		return
	num = current_upgrade["variable_zoom_scope"]["quantity"]
	penetrate_num += 1
	PlayerData.update_player_ability()

func bullet_add_penetrate(bullet_body: Node):
	if bullet_body != null:
		var ins = PoolManager.get_pool(pool_id)
		if ins == null or ins.is_idle == 0:
				ins = hit_flash.instantiate()
				get_tree().get_first_node_in_group("BulletRoot").add_child(ins)
		ins.position = bullet_body.global_position
		ins.rotation = bullet_body.rotation
		ins.active_state()
		bullet_body.penetrate += penetrate_num
