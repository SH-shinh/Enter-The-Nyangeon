extends Node2D

# 莲华人偶专用火场：参考 scenes/debuff/fire_field.gd，
# 但伤害为道具侧给定的固定值（无最大生命值百分比伤害）。
# is_idle / idle_state / active_state 供 renge_doll 的内置池复用。

@export var enemy_buff: Buff
@export var buff_layer: int = 1
@export var buff_value: float = 1.0
@export var buff_erase_timer: float = 1.0
@export var life_ticks: int = 20

@onready var hit_box = $Area2D
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

var value: Array
var field_damage: int = 0
var damage_cd: int = 2
var time_length: int = 20
var body_group: Array[Node] = []
var is_idle: int = 1
var is_ready: bool = false

func _ready() -> void:
	hit_box.area_entered.connect(_on_hit_box_entered)
	hit_box.area_exited.connect(_on_hit_box_exited)
	is_ready = true
	idle_state()

func idle_state():
	is_idle = 1
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	if not body_group.is_empty():
		body_group.clear()
	gpu_particles_2d.emitting = false
	self.visible = false
	self.global_position = Vector2.ZERO
	hit_box.set_deferred("monitoring", false)

func active_state():
	if is_ready == false:
		return
	is_idle = 0
	value = [buff_layer, buff_value, buff_erase_timer]
	damage_cd = 2
	time_length = life_ticks
	if not body_group.is_empty():
		body_group.clear()
	if not GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	self.visible = true
	gpu_particles_2d.emitting = true
	gpu_particles_2d.restart()
	hit_box.set_deferred("monitoring", true)
	apply_fire_damage_data()

func time_count():
	if damage_cd > 0:
		damage_cd -= 1
		if damage_cd <= 0:
			add_damage_data()
			damage_cd = 2
	if time_length > 0:
		time_length -= 1
		if time_length <= 0:
			idle_state()

func apply_fire_damage_data():
	hit_box.damage_data = DamageData.fill(hit_box.damage_data, {
		"knockback": 0,
		"type": GameTags.FIRE_DAMAGE,
		"source": GameTags.EQUIP,
		"node": self,
	})

func add_damage_data():
	if body_group.is_empty():
		return
	for i in body_group:
		if i == null or not is_instance_valid(i):
			continue
		hit_box.damage_data.base_damage = field_damage
		if not hit_box.damage_data.flags.has(GameTags.TRUE_DAMAGE):
			hit_box.damage_data.flags.append(GameTags.TRUE_DAMAGE)
		i.hit_received.emit(hit_box.damage_data)
		var body = i.owner
		if enemy_buff != null and body != null and is_instance_valid(body) and body.get("enemy_buff_manager") != null:
			body.enemy_buff_manager.apply_buff(enemy_buff, value)

func _on_hit_box_entered(hurtbox: Area2D):
	if hurtbox == null or not is_instance_valid(hurtbox):
		return
	if hurtbox is HurtBox and not body_group.has(hurtbox):
		body_group.push_back(hurtbox)

func _on_hit_box_exited(hurtbox: Area2D):
	if hurtbox == null or not is_instance_valid(hurtbox):
		return
	if hurtbox is HurtBox and body_group.has(hurtbox):
		body_group.remove_at(body_group.find(hurtbox))
