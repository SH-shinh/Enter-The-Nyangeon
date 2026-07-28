extends Node2D

@onready var ink_cartridge_icon: PackedScene = preload("res://scenes/update_item/ink_cartridge_icon.tscn")
@onready var small_explosion: PackedScene = preload("res://script/explosion_damage.tscn")
@onready var floor_paint: PackedScene = preload("res://script/floor_paint.tscn")

var rail_group: Array = []
var num: int

var color_num: int

var player: Node
var equip_luck: int
var equip_damage: int = 20

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.enemy_body.connect(add_explosion)

func first_activation():
	equip_damage = 20
	equip_luck = 5
	PlayerData.update_player_ability()
	var sprite_2d = ink_cartridge_icon.instantiate()
	rail_group = get_tree().get_nodes_in_group("Rail")
	for i in rail_group:
		if i.picatinny_rail_use == false:
			i.add_child(sprite_2d)
			i.picatinny_rail_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "ink_cartridge":
		return
	if current_upgrade["ink_cartridge"]["quantity"] == 1:
		return
	num = current_upgrade["ink_cartridge"]["quantity"]
	equip_damage += 20
	equip_luck += 5
	PlayerData.update_player_ability()

func explosion(body: Node):
	var ins = PoolManager.get_pool("player_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = small_explosion.instantiate()
		add_ins = true
	
	ins.global_position = body.global_position
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		ins.is_critical = true
		ins.explosion_damage = max(1, (equip_damage + player.stats.bullet_damage * 0.4) * player.stats.explosion_damage * player.stats.global_damage * player.stats.critical_damage * player.stats.equip_damage)
	else:
		ins.explosion_damage = max(1, (equip_damage + player.stats.bullet_damage * 0.4) * player.stats.explosion_damage * player.stats.global_damage * player.stats.equip_damage)
	ins.explosion_knockback = player.stats.bullet_knockback
	ins.explosion_range = 3 * player.stats.explosion_range
	ins.is_equip_shoot = true
	
	ins.active_state()
	if add_ins == true:
		get_tree().get_first_node_in_group("BulletRoot").add_child(ins)
	
	ins.is_small_explosion()
	
	var ins_2 = PoolManager.get_pool("floor_paint")
	if ins_2 == null or ins_2.is_idle == 0:
		ins_2 = floor_paint.instantiate()
		get_tree().get_first_node_in_group("FloorLayer").add_child(ins_2)
	
	ins_2.global_position = body.global_position
	ins_2.active_state()

func add_explosion(body: Node ,_bullet_body: Node):
	if randf_range(0,400) < equip_luck + player.stats.luck:
		explosion.call_deferred(body)
