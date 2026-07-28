extends Node2D

@export var stats: Stats
@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var fire_diffuse = preload("res://scenes/debuff/fire_diffuse.tscn")

var value: Array
var diffuse_group: Array[Node]
var ps_luck: int = 70
var now_t:int
var index: int = 0

func _ready():
	PlayerData.player_ability_changed_end.connect(dot_damage_count)
	GameEvents.enemy_body.connect(fire_dot_append_damage)
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	value = [buff_layer, buff_value, buff_erase_timer]

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		ps_luck = 100
		GameEvents.enemy_fire_hurt.connect(add_fire_diffuse)
	elif now_t == 2:
		ps_luck = 140
		PlayerData.fire_dot_layer_add += 5
		PlayerData.update_player_ability()
	elif now_t == 3:
		ps_luck = 1000
		PlayerData.fire_dot_layer_add += 8
		PlayerData.update_player_ability()

func fire_dot_append_damage(enemy_body: Node, bullet_body: Node):
	var luck = randf_range(0,200)
	if luck < (ps_luck + stats.luck):
		enemy_body.enemy_buff_manager.apply_buff(enemy_buff, value)
	
	if enemy_body.enemy_buff_manager.current_buff.has("fire_dot"):
		enemy_body.hurt_damage += max(1, stats.bullet_damage * stats.global_damage * 0.5)
		if now_t == 3:
			enemy_body.enemy_buff_manager.apply_buff(enemy_buff, value)

func dot_damage_count():
	stats.dot_damage *= 1.10
	PlayerData.emit_player_ability_changed()

func add_fire_diffuse(enemy_body: Node):
	
	var luck = randf_range(0, 200)
	if luck < 60 + stats.luck:
		var ins
		var max_value = diffuse_group.size()
		if max_value > 30:
			ins = diffuse_group[index]
			index = wrapi(index + 1, 0, max_value)
		else:
			ins = fire_diffuse.instantiate()
			get_tree().get_first_node_in_group("EquipLayer").call_deferred("add_child", ins)
			diffuse_group.push_back(ins)
		ins.global_position = enemy_body.global_position
		ins.call_deferred("reset")
