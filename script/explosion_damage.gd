extends Node2D

signal in_idle

var can_r: bool = false
var r_speed: int = 50
var acceleration: Vector2 = Vector2.ZERO
var target_position: Vector2

var explosion_damage: int = 0
var explosion_knockback: int = 0
var explosion_range: float = 5
var hit_direction: Vector2

var penetrate: int = 1 #穿透值
var direction: Vector2 = Vector2.RIGHT
var speed: int = 300
var collision_num: int = 0 #反弹次数
var bullet_damage: int = 0
var bullet_knockback: int = 0
var append_damage: int = 0 #追加伤害

var is_idle: int = 1

var player: Node

var is_critical: bool = false
var is_player_bullet: bool = false
var is_player_shoot: bool = false

var is_equip_shoot:bool = false

var enemy_group: Array[Node]
var damage_mult: float = 1
var is_ready: bool = false

@export var pool_id: String = "player_explosion"

@onready var explosion_smoke: PackedScene = preload("res://script/explosion.tscn")
@onready var small_explosion_smoke: PackedScene = preload("res://script/small_explosion.tscn")
@onready var range_explosion_smoke: PackedScene = preload("res://script/range_explosion.tscn")
@onready var timer = $Timer
@onready var collision_shape_2d: CollisionShape2D = $Area2D/CollisionShape2D
@onready var texture_rect: TextureRect = $TextureRect

func _ready():
	PoolManager.add_pool(pool_id,self)
	is_on_ready()

func idle_state():
	add_damage()
	is_idle = 1
	in_idle.emit()
	is_critical = false
	is_player_shoot = false
	is_player_bullet = false
	is_equip_shoot = false
	self.visible = false
	self.global_position = Vector2.ZERO
	damage_mult = 1
	collision_shape_2d.disabled = true
	if !enemy_group.is_empty():
		enemy_group.clear()

func active_state():
	if is_ready == false:
		return
	is_idle = 0
	self.visible = true
	collision_shape_2d.disabled = false
	collision_shape_2d.shape.radius = explosion_range * 10.0
	texture_rect.scale = Vector2(explosion_range * 0.2, explosion_range * 0.2)
	damage_mult = 1
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

func add_damage():
	if !enemy_group.is_empty():
		GameEvents.emit_explosion_quantity(enemy_group.size(), self)
		for i in enemy_group.size():
			hit_direction = (enemy_group[i].position - position).normalized()
			enemy_group[i].hurt_damage = explosion_damage * damage_mult
			enemy_group[i].hurt_knockback = explosion_knockback
			enemy_group[i].hurt_direction = hit_direction
			enemy_group[i].is_explosion_hit = true
			
			if is_player_bullet == true:
				GameEvents.emit_enemy_body(enemy_group[i],self)
				if is_player_shoot == true:
					GameEvents.emit_player_bullet_hit_enemy(self)
				if enemy_group[i].stats.hp <= explosion_damage:
					GameEvents.emit_player_bullet_kill_enemy(self)
		
			if is_critical == true:
				enemy_group[i].is_critical_hit = is_critical
				if is_player_bullet == true:
					GameEvents.emit_player_critical_hit_enemy(self)
			
			if is_equip_shoot == true:
				GameEvents.emit_equip_hit_enemy(enemy_group[i],self)
				if enemy_group[i].stats.hp <= explosion_damage:
					GameEvents.emit_equip_kill_enemy()
			
			enemy_group[i].emit_signal("is_hurt")
			
			

func _on_area_2d_body_entered(body):
	if is_idle == 1:
		return
	
	if body.is_in_group("Enemy") and !enemy_group.has(body):
		enemy_group.push_back(body)

func _on_timer_timeout():
	idle_state()


func _on_area_2d_body_exited(body: Node2D) -> void:
	if is_idle == 1:
		return
	
	if body.is_in_group("Enemy") and enemy_group.has(body):
		enemy_group.remove_at(enemy_group.find(body))
