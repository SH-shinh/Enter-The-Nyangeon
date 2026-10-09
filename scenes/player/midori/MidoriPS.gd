extends PlayerPS

@export var enemy_buff: Buff

@onready var poison_diffuse = preload("res://scenes/debuff/poison_diffuse.tscn")

var diffuse_group: Array[Node]
var enemy_num: int = 0
var diffuse_num: int = 0
var index: int = 0
var _last_diffuse_ms: int = 0

func _ready():
	super._ready()
	PlayerData.player_ability_changed_end.connect(dot_damage_count)
	apply_poison_bullet_dealt()


func ps_upgrade(t_num: int):
	super.ps_upgrade(t_num)
	if now_t == 1:
		diffuse_num = 1
		enemy_num = 5
		GameEvents.enemy_damage_taken_dead.connect(add_poison_diffuse)
	elif now_t == 2:
		diffuse_num = 2
		enemy_num = 10
	elif now_t == 3:
		player.damage_types.append(GameTags.POISON_DAMAGE)
		dot_damage_count()

func apply_poison_bullet_dealt():
	player.damage_dealt.append(func(victim: Node, actual_damage: float):
		if now_t <= 2:
			if stats.ammo + 1 < (stats.max_ammo * 0.5):
				return
		var value: Array = [1, actual_damage, 1.1]
		victim.enemy_buff_manager.apply_buff(enemy_buff, value)
		)

func add_poison_diffuse(final_damage: int, damage_data: DamageData, body_path: NodePath):
	
	var enemy_body: Node = get_node_or_null(body_path)
	if enemy_body == null:
		return
	
	if damage_data.damage_type.has(GameTags.POISON_DAMAGE):
		var has_tag = enemy_body.stats.tag_set.has("poison_diffuse")
		
		if has_tag:
			enemy_body.stats.tag_set["poison_diffuse"]["quantity"] -= 1
			if enemy_body.stats.tag_set["poison_diffuse"]["quantity"] > 0:
				_spawn_poison_diffuse(enemy_body, final_damage, enemy_body.stats.tag_set["poison_diffuse"]["quantity"])
			else: enemy_body.stats.tag_set.erase("poison_diffuse")
		else:
			_spawn_poison_diffuse(enemy_body, final_damage, diffuse_num)

# 0.1s CD 只拦生成：tag 计数照常扣减，爆发期严格减少毒扩散节点与飘字
func _spawn_poison_diffuse(enemy_body: Node, final_damage: int, count: int):
	var now_ms := Time.get_ticks_msec()
	if now_ms - _last_diffuse_ms < 100:
		return
	_last_diffuse_ms = now_ms
	
	var ins
	var max_value = diffuse_group.size()
	if max_value > 30:
		ins = diffuse_group[index]
		index = wrapi(index + 1, 0, max_value)
	else:
		ins = poison_diffuse.instantiate()
		get_tree().get_first_node_in_group("EquipLayer").call_deferred("add_child", ins)
		diffuse_group.push_back(ins)
	ins.global_position = enemy_body.global_position
	ins.buff_value = final_damage
	ins.diffuse_num = count
	ins.enemy_num = enemy_num
	ins.call_deferred("reset")


func dot_damage_count():
	stats.dot_damage *= 1.10
	
	if now_t >= 3:
		stats.bullet_damage *= stats.dot_damage
	
	PlayerData.emit_player_ability_changed()
