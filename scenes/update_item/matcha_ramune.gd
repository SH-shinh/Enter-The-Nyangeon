extends Node2D

@export var enemy_buff: Buff

var num: int
var player: Node
var base_explosion_range: float = 3.0
var explosion_damage: int = 1
var group: Array =[]
@onready var explosion_ins: PackedScene = preload("res://script/explosion_damage.tscn")
@onready var matcha_ramune_hat_icon = preload("res://scenes/update_item/matcha_ramune_icon.tscn")

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)

func first_activation():
	player = get_tree().get_first_node_in_group("Player")
	GameEvents.enemy_poison_hurt.connect(damage_count)
	var sprite_2d = matcha_ramune_hat_icon.instantiate()
	group = get_tree().get_nodes_in_group("Hat")
	for i in group:
		if i.hat_use == false:
			i.add_child(sprite_2d)
			i.hat_use = true
	

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "matcha_ramune":
		return
	if current_upgrade["matcha_ramune"]["quantity"] == 1:
		return
	num = current_upgrade["matcha_ramune"]["quantity"]

func damage_count(enemy_body: Node):
	if enemy_body.enemy_buff_manager.current_buff.has("fire_dot") and enemy_body.enemy_buff_manager.current_buff.has("poison_dot"):
		explosion_damage = enemy_body.enemy_buff_manager.current_buff["poison_dot"]["value"] * 1.2
		#enemy_body.enemy_buff_manager.remove_buff(enemy_buff)
		add_dot_explosion(enemy_body.global_position)

func add_dot_explosion(explosion_position: Vector2):
	
	var ins = PoolManager.get_pool("player_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = explosion_ins.instantiate()
		add_ins = true
	
	ins.global_position = explosion_position
	ins.explosion_damage = explosion_damage * player.stats.dot_damage * player.stats.explosion_damage
	ins.explosion_knockback = player.stats.bullet_knockback
	ins.explosion_range = max(1, player.stats.explosion_range * 0.5) * base_explosion_range
	
	ins.active_state()
	if add_ins == true:
		get_tree().get_first_node_in_group("BulletRoot").add_child(ins)
	ins.is_small_explosion()
