class_name OilBarrel
extends SceneProp

## 可破坏油桶：被玩家侧攻击命中 hit_count 次后爆炸。
## 爆炸为中性 AOE，对敌我双方（含召唤物）生效；可连锁引爆附近油桶。

const EXPLOSION_SCENE: PackedScene = preload("res://script/explosion_damage.tscn")
const CHAIN_GROUP := "DestructibleProp"

@export var explosion_damage: int = 30
@export var explosion_range: int = 6
@export var explosion_knockback: int = 250
@export var chain_radius: float = 90.0

var _detonated: bool = false

func _ready() -> void:
	super._ready()
	add_to_group(CHAIN_GROUP)

func on_destroyed() -> void:
	if _detonated:
		return
	_detonated = true
	explode()
	_chain()
	queue_free()

func explode() -> void:
	var ins = PoolManager.get_pool("player_explosion")
	var add_ins := false
	if ins == null or ins.is_idle == 0:
		ins = EXPLOSION_SCENE.instantiate()
		add_ins = true
	ins.global_position = global_position
	ins.damage_data = DamageData.fill(ins.damage_data, {
		"damage": explosion_damage,
		"knockback": explosion_knockback,
		"type": GameTags.EXPLOSION_DAMAGE,
		"source": GameTags.NEUTRAL,
	})
	ins.explosion_range = explosion_range
	if add_ins:
		get_tree().get_first_node_in_group("SELayer").add_child(ins)
	ins.damage_data.source_node = ins.get_path()
	ins.active_state()
	ins.is_explosion()

func _chain() -> void:
	if chain_radius <= 0.0:
		return
	for other in get_tree().get_nodes_in_group(CHAIN_GROUP):
		if other == self or other == null or not is_instance_valid(other):
			continue
		if other.global_position.distance_to(global_position) > chain_radius:
			continue
		if other.has_method("on_destroyed"):
			other.call_deferred("on_destroyed")
