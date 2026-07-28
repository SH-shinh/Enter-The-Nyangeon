extends Node2D

@onready var range_explosion: PackedScene = preload("res://script/explosion_damage.tscn")
@onready var cherino_matryoshka_icon = preload("res://scenes/update_item/cherino_matryoshka_icon.tscn")
@onready var range_explosion_anim = $RangeExplosion

var num: int
var player: Node
var explosion_num: int = 0
var group: Array = []

func _ready():
	player = get_tree().get_first_node_in_group("Player")
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	GameEvents.explosion_damage.connect(explosion_count)

func first_activation():
	var sprite_2d = cherino_matryoshka_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "cherino_matryoshka":
		return
	if current_upgrade["cherino_matryoshka"]["quantity"] == 1:
		return
	num = current_upgrade["cherino_matryoshka"]["quantity"]

func explosion_count(explosion_position: Vector2, explosion_range: float):
	explosion_num += 1
	if explosion_num > 10:
		explosion_num = 0
		add_range_explosion()

func add_range_explosion():
	var ins = PoolManager.get_pool("player_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = range_explosion.instantiate()
		add_ins = true
	
	ins.global_position = self.global_position
	var luck = randf_range(0, 100)
	if luck < player.stats.critical_luck:
		ins.is_critical = true
		ins.explosion_damage = (10 + player.stats.bullet_damage) * player.stats.explosion_damage * player.stats.global_damage * player.stats.critical_damage * player.stats.equip_damage
	else:
		ins.explosion_damage = (10 + player.stats.bullet_damage) * player.stats.explosion_damage * player.stats.global_damage * player.stats.equip_damage
	ins.explosion_knockback = player.stats.bullet_knockback
	ins.explosion_range = 5 * player.stats.explosion_range
	ins.is_equip_shoot = true
	
	ins.active_state()
	if add_ins == true:
		get_tree().get_first_node_in_group("BulletRoot").call_deferred("add_child", ins)
	
	range_explosion_anim.scale = Vector2(5 * player.stats.explosion_range, 5 * player.stats.explosion_range)
	range_explosion_anim.play_anim()
