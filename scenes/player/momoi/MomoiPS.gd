extends PlayerPS

@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var fire_diffuse = preload("res://scenes/debuff/fire_diffuse.tscn")

var value: Array
var diffuse_group: Array[Node]
var ps_luck: int = 70
var index: int = 0
var _last_diffuse_ms: int = 0

func _ready():
	super._ready()
	GameEvents.enemy_damage_taken.connect(fire_dot_append_damage)
	value = [buff_layer, buff_value, buff_erase_timer]

func ps_upgrade(t_num: int):
	super.ps_upgrade(t_num)
	
	if now_t == 1:
		ps_luck = 100
		GameEvents.enemy_damage_taken.connect(add_fire_diffuse)
	elif now_t == 2:
		ps_luck = 140
		PlayerData.fire_dot_layer_add += 5
		PlayerData.update_player_ability()
	elif now_t == 3:
		ps_luck = 1000
		PlayerData.fire_dot_layer_add += 8
		PlayerData.update_player_ability()

func fire_dot_append_damage(_final_damage: int, damage_data: DamageData, body_path: NodePath):
	var enemy_body:= get_node_or_null(body_path)
	if enemy_body == null:
		return
	var has_fire: bool = enemy_body.enemy_buff_manager.current_buff.has("fire_dot")
	if damage_data.damage_type.has(GameTags.BULLET_DAMAGE):
		var luck = randf_range(0,200)
		if luck < (ps_luck + stats.luck):
			enemy_body.enemy_buff_manager.apply_buff(enemy_buff, value)
			if has_fire and now_t >= 3:
				enemy_body.enemy_buff_manager.apply_buff(enemy_buff, value)
		
	if has_fire:
		enemy_body.health_component.damage_multiplier += 0.5

func dot_damage_count():
	stats.dot_damage *= 1.10
	PlayerData.emit_player_ability_changed()

func add_fire_diffuse(_final_damage: int, _damage_data: DamageData, body_path: NodePath):
	var luck = randf_range(0, 200)
	if luck < 60 + stats.luck:
		# 0.1s CD：命中频率远高于扩散实际生效频率，节流避免同批节点被反复重置
		var now_ms := Time.get_ticks_msec()
		if now_ms - _last_diffuse_ms < 100:
			return
		_last_diffuse_ms = now_ms
		var enemy_body:Node = get_node_or_null(body_path)
		if enemy_body == null:
			return
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
