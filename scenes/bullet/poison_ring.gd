extends Node2D

var player: Node
var poison_damage: int = 0
var value: Array
@export var enemy_buff: Buff
@export var buff_layer: int
@export var buff_value: float
@export var buff_erase_timer: float

@onready var hit_box = $HitBox
@onready var collision_shape_2d: CollisionShape2D = $HitBox/CollisionShape2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D

var _shape_gen: int = 0

# 统一形状启停出口：自增代数并延迟写入，作废同帧残留的旧延迟调用，
# 避免在物理 query flush 期直接写 Area2D 形状（area_set_shape_disabled 报错）。
func _request_shape_disabled(value: bool) -> void:
	_shape_gen += 1
	call_deferred("_set_shape_disabled_guarded", value, _shape_gen)

func _set_shape_disabled_guarded(value: bool, gen: int) -> void:
	if gen != _shape_gen:
		return
	collision_shape_2d.disabled = value

func idle_state():
	poison_damage = 0
	self.global_position = Vector2.ZERO
	self.visible = false
	_request_shape_disabled(true)
	gpu_particles_2d.emitting = false

func active_state():
	self.visible = true
	animation_player.play("new_animation")
	apply_poison_dealt()

func gpu_emitting():
	gpu_particles_2d.emitting = true
	gpu_particles_2d.restart()

func apply_poison_dealt():
	if hit_box.damage_data == null:
		return
	hit_box.damage_data.on_damage_dealt.clear()
	hit_box.damage_data.on_damage_dealt.append(func(victim: Node, actual_damage: float):
		if victim == null or not is_instance_valid(victim):
			return
		var manager = victim.get("enemy_buff_manager")
		if manager == null:
			return
		buff_value = actual_damage
		value = [buff_layer, buff_value, buff_erase_timer]
		manager.apply_buff(enemy_buff, value)
	)
