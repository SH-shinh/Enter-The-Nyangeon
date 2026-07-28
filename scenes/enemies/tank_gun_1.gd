extends Node2D

@export var stats: EnemyStats
@export var gun_shoot_num: int = 3
@export var tank_bullet: PackedScene
@export var pool_id: String
@export var shoot_offeset: float
@export var explosion_range: float = 5
@export var shoot_bullet_num: int = 12

signal shoot_end

@onready var marker_2d: Marker2D = $Marker2D
@onready var shoot_flash = preload("res://scenes/enemies/cannon_flash.tscn")
@onready var timer = $Timer

var player: Node

func shoot_bullet():
	SoundManager.play_sfx("CannonSounds2")
	var now_shoot_flash = PoolManager.get_pool("cannon_flash_1")
	if now_shoot_flash == null or now_shoot_flash.is_idle == 0:
		now_shoot_flash = shoot_flash.instantiate()
		get_tree().get_first_node_in_group("SELayer").add_child(now_shoot_flash)
	now_shoot_flash.position = marker_2d.global_position
	now_shoot_flash.rotation = global_rotation
	now_shoot_flash.active_state()
	add_tank_bullet()

func add_tank_bullet():
	for i in gun_shoot_num:
		var tank_bullet_ins = PoolManager.get_pool(pool_id)
		if tank_bullet_ins == null or tank_bullet_ins.is_idle == 0:
			tank_bullet_ins = tank_bullet.instantiate()
			get_tree().get_first_node_in_group("SELayer").add_child(tank_bullet_ins)
		
		if player != null:
			var shoot_p = player.global_position + Vector2(randf_range(-shoot_offeset,shoot_offeset),randf_range(-shoot_offeset,shoot_offeset))
			tank_bullet_ins.global_position = shoot_p
			tank_bullet_ins.explosion_range = explosion_range
			tank_bullet_ins.knockback = stats.Enemy_Knockback
			tank_bullet_ins.bullet_damage = stats.Enemy_bullet_damage * stats.bullet_damage_mult
			tank_bullet_ins.shoot_bullet_num = shoot_bullet_num
			tank_bullet_ins.bullet_damage_mult = stats.bullet_damage_mult
			tank_bullet_ins.active_state()

func gun_shot():
	if player == null:
		player = get_tree().get_first_node_in_group("Player")
	shoot_bullet()
	shoot_end.emit()
