extends Node2D

signal is_end

@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float
@onready var area_2d = $Area2D
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

var value: Array
var hp_mult: float = 0.05
var add_end: bool = true
var damage_cd: int = 3
var damage_count: int = 0
var player: Node
var time_length: int = 30
var enemy_group: Array[Node]
var is_idle: int = 1
var is_ready: bool = false

func _ready() -> void:
	is_on_ready()

func is_on_ready():
	is_ready = true
	GameEvents.round_end.connect(idle_state)
	active_state()
	player = get_tree().get_first_node_in_group("Player")

func idle_state():
	is_idle = 1
	if !enemy_group.is_empty():
		enemy_group.clear()
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	gpu_particles_2d.emitting = false
	self.visible = false
	self.global_position = Vector2.ZERO
	area_2d.set_deferred("monitoring" , false)
	area_2d.set_deferred("monitorable" , false)

func active_state():
	
	if is_ready == false:
		return
	
	is_idle = 0
	value = [buff_layer, buff_value, buff_erase_timer]
	damage_cd = 3
	damage_count = 0
	time_length = 30
	if !enemy_group.is_empty():
		enemy_group.clear()
	if !GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	self.visible = true
	gpu_particles_2d.emitting = true
	gpu_particles_2d.restart()
	area_2d.set_deferred("monitoring" , true)
	area_2d.set_deferred("monitorable" , true)

func time_count():
	if damage_cd > 0:
		damage_cd -= 1
		if damage_cd <= 0:
			add_damage()
			damage_cd = 3
	
	if time_length > 0:
		time_length -= 1
		if time_length <= 0:
			time_length = 30
			idle_state()
	

func add_damage():
	if !enemy_group.is_empty():
		for i in enemy_group.size():
			var damage_value: int
			if damage_count < 8:
				damage_value = 8 * player.stats.fire_dot_layer * player.stats.dot_damage * player.stats.global_damage
			else:
				damage_count = 0
				damage_value = enemy_group[i].stats.max_hp * hp_mult
				if enemy_group[i].is_in_group("BOSS"):
					damage_value = enemy_group[i].stats.max_hp * 0.01
			enemy_group[i].hurt_damage = damage_value
			enemy_group[i].hurt_knockback = 0
			enemy_group[i].hurt_direction = Vector2.ZERO
			enemy_group[i].is_fire_hit = true
			enemy_group[i].emit_signal("is_hurt")
			enemy_group[i].enemy_buff_manager.apply_buff(enemy_buff, value)
			damage_count += 1

func _on_area_2d_body_entered(body):
	if body.is_in_group("Enemy") and !enemy_group.has(body):
		enemy_group.push_back(body)


func _on_area_2d_body_exited(body):
	if body.is_in_group("Enemy") and enemy_group.has(body):
		enemy_group.remove_at(enemy_group.find(body))
