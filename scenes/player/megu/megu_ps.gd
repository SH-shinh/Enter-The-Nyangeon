extends Node2D

@export var stats: Stats

@onready var fire_field = preload("res://scenes/debuff/fire_field.tscn")

var value: Array
var fire_group: Array[Node]
var ps_luck: int = 20
var now_t:int
var index: int = 0

func _ready():
	GameEvents.player_ps_upgrade.connect(ps_upgrade)
	PlayerData.set_player.connect(set_playerdata)

func ps_upgrade(t_num: int):
	now_t = t_num
	
	if now_t == 1:
		ps_luck = 20
		GameEvents.player_bullet_free_position.connect(add_fire_field)
		pass
	elif now_t == 2:
		PlayerData.fire_dot_layer_add += 6
		PlayerData.update_player_ability()
	elif now_t == 3:
		GameEvents.player_shot_position.connect(add_fire_bullet)

func set_playerdata():
	PlayerData.bullet_damage_mult = 0.4

func add_fire_bullet(_shoot_position: Vector2, bullet: Node):
	if bullet.get("can_block") != null:
		bullet.can_block = false

func add_fire_field(free_position: Vector2):
	
	var luck = randf_range(0, 200)
	if luck < ps_luck + stats.luck:
		var ins
		var max_value = fire_group.size()
		if max_value > 20:
			ins = fire_group[index]
			index = wrapi(index + 1, 0, max_value)
		else:
			ins = fire_field.instantiate()
			get_tree().get_first_node_in_group("SELayer").call_deferred("add_child", ins)
			fire_group.push_back(ins)
		ins.global_position = free_position
		ins.active_state()
