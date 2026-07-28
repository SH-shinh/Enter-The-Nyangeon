extends Node2D

var explosion_damage: int = 0
var explosion_knockback: int = 0
var explosion_range: float = 5
var hit_direction: Vector2

var is_idle: int = 1

@export var pool_id: String = "enemy_explosion"

@onready var timer = $Timer

@onready var explosion_smoke: PackedScene = preload("res://script/explosion.tscn")
@onready var small_explosion_smoke: PackedScene = preload("res://script/small_explosion.tscn")
@onready var collision_shape_2d: CollisionShape2D = $Area2D/CollisionShape2D

func _ready():
	scale = Vector2(explosion_range, explosion_range)
	PoolManager.add_pool(pool_id,self)
	timer.start()

func idle_state():
	is_idle = 1
	self.visible = false
	self.global_position = Vector2.ZERO

func active_state():
	is_idle = 0
	self.visible = true
	scale = Vector2(explosion_range, explosion_range)
	if timer != null:
		timer.start()

func is_explosion():
	
	var ins = PoolManager.get_pool("big_explosion")
	var add_ins: bool = false
	if ins == null or ins.is_idle == 0:
		ins = explosion_smoke.instantiate()
		add_ins = true
	
	ins.global_position = global_position
	ins.shoot = false
	if add_ins == true:
		get_tree().get_first_node_in_group("SELayer").add_child(ins)
	ins.active_state()
	SoundManager.play_sfx("ExplosionSounds")

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
	SoundManager.play_sfx("ExplosionSounds")

func _on_area_2d_body_entered(body):
	if body.is_in_group("Player"):
		if body.invincible_frame.time_left > 0:
			return
		hit_direction = (body.global_position - global_position).normalized()
		
		
		body.hurt_damage = explosion_damage
		body.hurt_knockback = explosion_knockback
		body.hurt_dir = hit_direction
		body.emit_signal("is_hurt")

func _on_timer_timeout():
	idle_state()


func _on_area_2d_area_shape_entered(area_rid: RID, area: Area2D, area_shape_index: int, local_shape_index: int) -> void:
	if area.is_in_group("SummonedBox"):
		if area.on_hit == false:
			hit_direction = (area.global_position - global_position).normalized()
			area.hurt_knockback = explosion_knockback
			area.hurt_dir = hit_direction
			area.count_damage(explosion_damage)
