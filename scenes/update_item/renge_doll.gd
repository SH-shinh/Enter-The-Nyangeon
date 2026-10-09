extends EquipItem

# 莲华人偶：随人偶移动，每0.2秒在其位置留下一个火场，形成火蛇拖尾。
# 火场由道具内置池复用（field_group + pool_index）。

@onready var renge_doll_icon: PackedScene = preload("res://scenes/update_item/renge_doll_icon.tscn")
@onready var renge_fire_field: PackedScene = preload("res://scenes/update_item/renge_fire_field.tscn")

const PLACE_INTERVAL: int = 2       # 2 tick @ 10Hz = 0.2s
const BASE_DAMAGE: int = 15
const DAMAGE_PER_LEVEL: int = 20

@export var field_cap: int = 12

var player: Node
var doll: Node
var field_group: Array[Node] = []
var pool_index: int = 0
var tick: int = 0
var field_base_damage: int = BASE_DAMAGE

func _on_equip():
	player = get_tree().get_first_node_in_group("Player")
	spawn_doll()

func _setup():
	GameEvents.global_time_count.connect(time_count)

func _apply_effect(quantity: int):
	field_base_damage = BASE_DAMAGE + DAMAGE_PER_LEVEL * (quantity - 1)

func spawn_doll():
	if player == null:
		return
	var ins = renge_doll_icon.instantiate()
	for i in get_tree().get_nodes_in_group("Follow"):
		if i.follow_use == false:
			get_tree().get_first_node_in_group("PlayerRoot").add_child(ins)
			ins.get_follow(i)
			i.follow_use = true
			doll = ins
			break

func time_count():
	tick += 1
	if tick < PLACE_INTERVAL:
		return
	tick = 0
	place_field()

func place_field():
	if doll == null or not is_instance_valid(doll):
		return
	if player == null or player.get("stats") == null:
		return
	var field = get_field()
	if field == null:
		return
	var damage_value: int = int(field_base_damage * player.stats.global_damage * player.stats.dot_damage * player.stats.equip_damage)
	field.field_damage = max(1, damage_value)
	field.global_position = doll.global_position
	field.active_state()
	ExtensionHooks.notify(ExtensionHooks.on_visual_activated, [field])

# 内置池：优先取空闲火场；满上限则循环复用最旧的并强制复位。
func get_field() -> Node:
	for f in field_group:
		if f.is_idle == 1:
			return f
	if field_group.size() >= field_cap:
		var f: Node = field_group[pool_index]
		pool_index = wrapi(pool_index + 1, 0, field_group.size())
		f.idle_state()
		return f
	var f = renge_fire_field.instantiate()
	get_tree().get_first_node_in_group("SELayer").add_child(f)
	field_group.push_back(f)
	return f
