extends Node2D

signal spawn

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D
@onready var gpu_particles_2d_2: GPUParticles2D = $GPUParticles2D2
@onready var gpu_particles_2d_3: GPUParticles2D = $GPUParticles2D3

var hp_mult = 1
var damage_mult = 1

var is_boss: bool = false

var is_idle: int = 1

var has_path: bool = false
var path: PackedScene
var path_value: float
var coin_mult: float = 1

var can_spawn: bool = true

func _ready():
	PoolManager.add_pool("spawn_anim", self)
	GameEvents.round_end.connect(on_round_end)

func idle_state():
	is_idle = 1
	coin_mult = 1
	has_path = false
	is_boss = false
	self.visible = false
	self.global_position = Vector2.ZERO

func active_state():
	is_idle = 0
	self.visible = true
	gpu_particles_2d.restart()
	gpu_particles_2d_2.restart()
	#gpu_particles_2d_3.restart()

func emit_spawn():
	spawn.emit()

func enemy_spawn_anim(enemy: EnemyCard):
	if is_boss == false:
		self.visible = true
	else:
		self.visible = false
	animation_player.play("new_animation")
	await spawn
	if can_spawn == true:
		spawn_enemy_body(enemy)

func spawn_enemy_body(enemy: EnemyCard):
	var enemy_body = PoolManager.get_pool(enemy.id)
	if enemy_body == null or enemy_body.is_idle == 0:
		enemy_body = enemy.body.instantiate()
		get_tree().get_first_node_in_group("EnemiesRoot").add_child(enemy_body)
		var path_ins
		if has_path == true:
			path_ins = path.instantiate()
			enemy_body.add_child(path_ins)
			path_ins.path_follow_2d.progress_ratio = path_value
			path_ins.enemy_body = enemy_body
			path_ins.active_state()
			path_ins.set_body_target()
	
	enemy_body.global_position = global_position
	enemy_body.stats.max_hp_mult = hp_mult
	enemy_body.stats.Enemy_damage_mult = damage_mult
	enemy_body.stats.Enemy_bullet_damage_mult = damage_mult
	enemy_body.stats.Enemy_coin *= coin_mult
	enemy_body.stats.update_body_ability()
	enemy_body.active_state()
	if enemy_body.body_part != null:
		for i in enemy_body.body_part.size():
			enemy_body.body_part[i].stats.max_hp_mult = hp_mult
			enemy_body.body_part[i].stats.update_body_ability()
			enemy_body.body_part[i].active_state()

func on_round_end():
	can_spawn = false
	PoolManager.erase_pool("spawn_anim")
	queue_free()
