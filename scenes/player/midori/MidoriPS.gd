extends Node2D

@export var stats: Stats

@onready var poison_bullet = preload("res://scenes/debuff/poison_bullet.tscn")
@onready var poison_diffuse = preload("res://scenes/debuff/poison_diffuse.tscn")

var now_t: int = 0
var diffuse_group: Array[Node]
var enemy_num: int = 0
var diffuse_num: int = 0
var index: int = 0

func _ready():
	PlayerData.player_ability_changed_end.connect(dot_damage_count)
	GameEvents.player_shot_position.connect(poison_bullet_add)
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	GameEvents.enemy_poison_hurt.connect(add_poison_diffuse)


func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		diffuse_num = 1
		enemy_num = 5
	elif now_t == 2:
		diffuse_num = 2
		enemy_num = 10
	elif now_t == 3:
		dot_damage_count()

func poison_bullet_add(shot_position: Vector2, bullet_body: Node):
	
	if now_t <= 2:
		if stats.ammo >= (stats.max_ammo * 0.5):
			var ins = poison_bullet.instantiate()
			bullet_body.add_child(ins)
	elif now_t > 2:
		var ins = poison_bullet.instantiate()
		bullet_body.add_child(ins)

func add_poison_diffuse(enemy_body: Node):
	if now_t < 1:
		return
	
	if enemy_body.stats.hp <= 0:
		var ins
		var max_value = diffuse_group.size()
		var has_tag = enemy_body.stats.tag_set.has("poison_diffuse")
		
		if has_tag:
			enemy_body.stats.tag_set["poison_diffuse"]["quantity"] -= 1
			if enemy_body.stats.tag_set["poison_diffuse"]["quantity"] > 0:
				if max_value > 30:
					ins = diffuse_group[index]
					index = wrapi(index + 1, 0, max_value)
				else:
					ins = poison_diffuse.instantiate()
					get_tree().get_first_node_in_group("EquipLayer").call_deferred("add_child", ins)
					diffuse_group.push_back(ins)
				ins.global_position = enemy_body.global_position
				ins.buff_value = enemy_body.stats.hurt_hp
				ins.buff_erase_timer *= stats.dot_time
				ins.diffuse_num = enemy_body.stats.tag_set["poison_diffuse"]["quantity"]
				ins.enemy_num = enemy_num
				ins.call_deferred("reset")
			else: enemy_body.stats.tag_set.erase("poison_diffuse")
		else:
			if max_value > 30:
				ins = diffuse_group[index]
				index = wrapi(index + 1, 0, max_value)
			else:
				ins = poison_diffuse.instantiate()
				get_tree().get_first_node_in_group("EquipLayer").call_deferred("add_child", ins)
				diffuse_group.push_back(ins)
			ins.global_position = enemy_body.global_position
			ins.buff_value = enemy_body.stats.hurt_hp
			ins.buff_erase_timer *= stats.dot_time
			ins.diffuse_num = diffuse_num
			ins.enemy_num = enemy_num
			ins.call_deferred("reset")


func dot_damage_count():
	stats.dot_damage *= 1.10
	
	if now_t >= 3:
		stats.bullet_damage *= stats.dot_damage
	
	PlayerData.emit_player_ability_changed()
