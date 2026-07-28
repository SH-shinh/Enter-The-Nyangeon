extends Node2D

@onready var stone_bullet: PackedScene = preload("res://scenes/bullet/stone_bullet.tscn")
@onready var cd_timer = $CDTimer

var rail_group: Array = []
var num: int

var color_num: int

var player: Node
var equip_luck: int

var equip_mult: float
var is_critical: bool

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.enemy_hit_position.connect(add_stone_bullet)


func first_activation():
	equip_mult = 0.8
	equip_luck = 10

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "winnipesaukee_stone":
		return
	if current_upgrade["winnipesaukee_stone"]["quantity"] == 1:
		return
	num = current_upgrade["winnipesaukee_stone"]["quantity"]
	equip_mult += 0.8

func bullet_damage_count():
	var damage: int
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		damage = max(1, round((player.stats.max_hp + player.stats.t_hp) * equip_mult * player.stats.global_damage * player.stats.equip_damage * player.stats.critical_damage))
		is_critical = true
	else:
		damage = max(1, round((player.stats.max_hp + player.stats.t_hp) * equip_mult * player.stats.global_damage * player.stats.equip_damage))
		is_critical = false
	return damage

func shoot_bullet(hit_body: Node):
	
	var ins = PoolManager.get_pool("stone_bullet")
	if ins == null or ins.is_idle == 0:
		ins = stone_bullet.instantiate()
		get_tree().get_first_node_in_group("BulletRoot").add_child(ins)
	
	ins.global_position = hit_body.global_position
	ins.equip_damage = bullet_damage_count()
	ins.equip_knockback = player.stats.bullet_knockback
	ins.is_critical = is_critical
	
	var luck = randf_range(0, 100)
	if luck < equip_luck:
		ins.yuuka_bullet()
	else:
		ins.stone_bullet()
	ins.active_state()

func add_stone_bullet(hit_body: Node):
	
	if cd_timer.time_left <= 0:
		cd_timer.start()
		shoot_bullet.call_deferred(hit_body)
	
