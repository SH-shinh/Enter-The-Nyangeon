extends Node2D

signal is_end

@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@onready var hit_box = $Area2D
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

var value: Array
var hp_mult: float = 0.05
var add_end: bool = true
var damage_cd: int = 2
var damage_count: int = 0
var player: Node
var time_length: int = 30
var body_group: Array[Node]
var is_idle: int = 1
var is_ready: bool = false

func _ready() -> void:
	hit_box.area_entered.connect(_on_hit_box_entered)
	hit_box.area_exited.connect(_on_hit_box_exited)
	is_on_ready()

func is_on_ready():
	is_ready = true
	GameEvents.round_end.connect(idle_state)
	active_state()
	player = get_tree().get_first_node_in_group("Player")

func idle_state():
	is_idle = 1
	if !body_group.is_empty():
		body_group.clear()
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	gpu_particles_2d.emitting = false
	self.visible = false
	self.global_position = Vector2.ZERO
	hit_box.set_deferred("monitoring" , false)

func active_state():
	
	if is_ready == false:
		return
	
	is_idle = 0
	value = [buff_layer, buff_value, buff_erase_timer]
	damage_cd = 2
	damage_count = 0
	time_length = 30
	if !body_group.is_empty():
		body_group.clear()
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	self.visible = true
	gpu_particles_2d.emitting = true
	gpu_particles_2d.restart()
	hit_box.set_deferred("monitoring" , true)
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
			time_length = 30
			idle_state()	

func apply_fire_damage_data():
	if hit_box.damage_data == null:
		hit_box.damage_data = DamageData.new()
	else:
		hit_box.damage_data.reset_data()
	
	hit_box.damage_data.knockback_force = 0
	hit_box.damage_data.damage_type.append(GameTags.FIRE_DAMAGE)
	hit_box.damage_data.source_node = self.get_path()
	hit_box.damage_data.source_type.append(GameTags.PS_DAMAGE)

func add_damage_data():
	if !body_group.is_empty():
		for i in body_group:
			if i == null or not is_instance_valid(i):
				continue
			var damage_value: int
			if damage_count < 8:
				damage_value = 8 * player.stats.fire_dot_layer * player.stats.dot_damage * player.stats.global_damage
			else:
				damage_count = 0
				damage_value = i.owner.stats.max_hp * hp_mult
				if i.owner.is_in_group("BOSS"):
					damage_value = i.owner.stats.max_hp * 0.01
			hit_box.damage_data.base_damage = damage_value
			hit_box.damage_data.flags.append(GameTags.TRUE_DAMAGE)
			i.hit_received.emit(hit_box.damage_data)
			i.owner.enemy_buff_manager.apply_buff(enemy_buff, value)
			damage_count += 1

func _on_hit_box_entered(hurtbox: Area2D):
	if hurtbox is HurtBox and !body_group.has(hurtbox):
		body_group.push_back(hurtbox)

func _on_hit_box_exited(hurtbox: Area2D):
	if hurtbox is HurtBox and body_group.has(hurtbox):
		body_group.remove_at(body_group.find(hurtbox))
