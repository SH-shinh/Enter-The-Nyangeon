extends Node2D

var num: int
var player: Node
var poison_damage: int
var damage_mult: float = 0.4
var group: Array = []
var doll: Node

var ring: Node

var poison_cd: int = 40
var now_cd: int = 40

@onready var kikyou_doll_icon = preload("res://scenes/update_item/kikyou_doll_icon.tscn")
@onready var poison_ring: PackedScene = preload("res://scenes/bullet/poison_ring.tscn")

func _ready():
	first_activation()
	GameEvents.ability_upgrade_added.connect(on_upgrade_added)
	PlayerData.player_ability_changed_end.connect(update_poison_damage)
	GameEvents.global_time_count.connect(time_count)

func time_count():
	if now_cd > 0:
		now_cd -= 1
		if now_cd <= 0:
			add_poison_ring()
			now_cd = poison_cd

func first_activation():
	now_cd = poison_cd
	damage_mult = 0.4
	player = get_tree().get_first_node_in_group("Player")
	update_poison_damage()
	var sprite_2d = kikyou_doll_icon.instantiate()
	group = get_tree().get_nodes_in_group("Follow")
	for i in group:
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(sprite_2d)
			sprite_2d.get_follow(i)
			i.follow_use = true
			doll = sprite_2d

func add_poison_ring():
	if ring != null:
		if doll != null:
			ring.poison_damage = poison_damage
			ring.global_position = doll.global_position
			ring.active_state()
	else:
		var ins = poison_ring.instantiate()
		get_tree().get_first_node_in_group("SELayer").add_child(ins)
		ins.poison_damage = poison_damage
		ins.global_position = doll.global_position
		ins.active_state()
		ring = ins

func update_poison_damage():
	poison_damage = max(1, player.stats.bullet_damage * player.stats.equip_damage * damage_mult)

func on_upgrade_added(upgrade: AbilityUpgrade, current_upgrade: Dictionary):
	if upgrade.id != "kikyou_doll":
		return
	if current_upgrade["kikyou_doll"]["quantity"] == 1:
		return
	num = current_upgrade["kikyou_doll"]["quantity"]
	damage_mult += 0.15
	update_poison_damage()
