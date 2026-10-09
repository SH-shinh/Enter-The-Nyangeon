class_name ExplosionDamage
extends HitBox

signal in_idle

var can_r: bool = false
var r_speed: int = 50
var acceleration: Vector2 = Vector2.ZERO
var target_position: Vector2

var explosion_range: float = 5

var penetrate: int = 1 #穿透值
var direction: Vector2 = Vector2.RIGHT
var speed: int = 300
var collision_num: int = 0 #反弹次数

var is_idle: int = 1

var player: Node

var enemy_group: Array[Area2D]
var enemy_size: int = 0
var damage_mult: float = 1
var flight_time: float = 0.0
var is_ready: bool = false

@export var pool_id: String = "player_explosion"

@onready var explosion_smoke: PackedScene = preload("res://script/explosion.tscn")
@onready var small_explosion_smoke: PackedScene = preload("res://script/small_explosion.tscn")
@onready var range_explosion_smoke: PackedScene = preload("res://script/range_explosion.tscn")
@onready var timer = $Timer
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var texture_rect: TextureRect = $TextureRect

func _ready():
	PoolManager.add_pool(pool_id,self)
	is_on_ready()

func idle_state():
	GameEvents.emit_explosion_quantity(enemy_group.size(), self)
	add_damage_data()
	is_idle = 1
	in_idle.emit()
	self.visible = false
	self.global_position = Vector2.ZERO
	damage_mult = 1
	collision_shape_2d.set_deferred("disabled", true)

# 对象池满额强收时的无副作用回收：不结算伤害、不广播数量、不发 in_idle。
# 正常自然到期仍走 idle_state()。
func deactivate_silent():
	is_idle = 1
	if timer != null:
		timer.stop()
	if enemy_group != null:
		enemy_group.clear()
	self.visible = false
	self.global_position = Vector2.ZERO
	damage_mult = 1
	collision_shape_2d.set_deferred("disabled", true)

func active_state():
	if is_ready == false:
		return
	is_idle = 0
	self.visible = true
	GameEvents.emit_player_explosion_damage(damage_data)
	if !enemy_group.is_empty():
		enemy_group.clear()
	collision_shape_2d.set_deferred("disabled", false)
	collision_shape_2d.shape.radius = explosion_range * 10.0
	texture_rect.scale = Vector2(explosion_range * 0.2, explosion_range * 0.2)
	damage_mult = 1
	flight_time = 0.0
	enemy_size = 0
	if timer != null:
		timer.start()
	

func is_on_ready():
	is_ready = true
	active_state()

func is_explosion():
	
	var ins = PoolManager.get_pool("big_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = explosion_smoke.instantiate()
		add_ins = true
	
	ins.global_position = global_position
	if add_ins == true:
		get_tree().get_first_node_in_group("SELayer").add_child(ins)
	ins.active_state()
	GameEvents.emit_explosion_damage(self.global_position, 10 * explosion_range)
	SoundManager.play_sfx("ExplosionSounds")
	ExtensionHooks.notify(ExtensionHooks.on_explosion_effect, [global_position, true])

func is_small_explosion():
	
	var ins = PoolManager.get_pool("small_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = small_explosion_smoke.instantiate()
		add_ins = true
	
	ins.global_position = global_position
	if add_ins == true:
		get_tree().get_first_node_in_group("SELayer").add_child(ins)
	ins.active_state()
	GameEvents.emit_explosion_damage(self.global_position, 10 * explosion_range)
	SoundManager.play_sfx("ExplosionSounds")
	ExtensionHooks.notify(ExtensionHooks.on_explosion_effect, [global_position, false])

func add_damage_data():
	if enemy_group.is_empty():
		return
	var data: DamageData = damage_data
	if data == null:
		return
	data.hit_box_center = global_position
	# 玩家侧爆炸统一吃「爆炸伤害」加成（类型驱动，取代各创建点手写乘算）。

	data = apply_player_explosion_bonus(data, _get_player())
	for i in enemy_group:
		if i == null or not is_instance_valid(i):
			continue
		i.hit_received.emit(data)

func _get_player() -> Node:
	var p: Node = PlayerData.player
	if p != null and is_instance_valid(p) and p.is_inside_tree():
		return p
	return PlayerRef.resolve(self)

# 玩家侧爆炸是否吃「爆炸伤害」加成：类型含 EXPLOSION_DAMAGE，来源非空且属玩家侧。
# 来源必须非空——空 source_type 会被 Faction.of_source 判成玩家方（见 docs/LEARNINGS.md）。
static func should_apply_player_explosion_bonus(damage_type: Array, source_type: Array) -> bool:
	return damage_type.has(GameTags.EXPLOSION_DAMAGE) \
		and not source_type.is_empty() \
		and Faction.of_source(source_type) == Faction.PLAYER_SIDE

# 返回应用加成后的 DamageData（复制后改写，不污染原实例）；不适用/无玩家时原样返回。
static func apply_player_explosion_bonus(data: DamageData, player: Node) -> DamageData:
	if data == null or player == null or not is_instance_valid(player):
		return data
	if not should_apply_player_explosion_bonus(data.damage_type, data.source_type):
		return data
	var player_stats = player.get("stats")
	if player_stats == null:
		return data
	var out: DamageData = data.duplicate(true)
	out.base_damage = max(1, int(round(out.base_damage * player_stats.explosion_damage)))
	return out

func _on_timer_timeout():
	idle_state()

func _on_area_entered(hurtbox: Area2D):
	if is_idle == 1:
		return
	if damage_data == null:
		return
	if hurtbox is HurtBox and !enemy_group.has(hurtbox):
		if Faction.hostile_to(damage_data.source_type, Faction.of_entity(hurtbox.owner)):
			enemy_group.push_back(hurtbox)
