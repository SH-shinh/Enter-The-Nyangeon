extends Node2D

@export var enemy_buff: Buff
@export var add_layer: int = 3
@export var chill_layer_cap: int = 5
@export var source_id: String = ""
@export var buff_erase_timer: float = 3.0

var value: Array
var is_idle: int = 1
var enemy_group: Array[Node] = []

@onready var hit_box: Area2D = $HitBox
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

func _ready():
	hit_box.body_entered.connect(_on_body_entered)
	hit_box.body_exited.connect(_on_body_exited)
	idle_state()

func idle_state():
	is_idle = 1
	visible = false
	global_position = Vector2.ZERO
	hit_box.set_deferred("monitoring", false)

func active_state():
	is_idle = 0
	visible = true
	animation_player.play("new_animation")
	hit_box.set_deferred("monitoring", true)

func gpu_emitting():
	gpu_particles_2d.restart()

func _on_body_entered(body):
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Enemy") and not enemy_group.has(body):
		enemy_group.push_back(body)
		_apply_chill(body)

func _on_body_exited(body):
	if body == null or not is_instance_valid(body):
		return
	if enemy_group.has(body):
		enemy_group.erase(body)

func _apply_chill(enemy):
	if enemy == null or not is_instance_valid(enemy):
		return
	var manager = enemy.get("enemy_buff_manager")
	if manager == null:
		return
	value = [chill_layer_cap, 0.0, buff_erase_timer]
	for i in add_layer:
		manager.apply_buff(enemy_buff, value, source_id)
