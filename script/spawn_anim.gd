extends Node2D

signal spawn

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var gpu_particles_2d: GPUParticles2D = $GPUParticles2D
@onready var gpu_particles_2d_2: GPUParticles2D = $GPUParticles2D2
@onready var gpu_particles_2d_3: GPUParticles2D = $GPUParticles2D3

# 路线型敌人（EnemyCard.route 非空）在未显式提供路径时的兜底，保证不会静默丢失路线。
const DEFAULT_ROUTE: PackedScene = preload("res://scenes/enemies/enemies_spawn/enemy_path.tscn")

var hp_mult = 1
var damage_mult = 1

var is_boss: bool = false

var is_idle: int = 1

var has_path: bool = false
var path: PackedScene
var path_value: float
var coin_mult: float = 1

var can_spawn: bool = true

# 本次生成预占的敌人 id（并发上限）；生成完成或中止时释放，防 pending 泄漏
var _claimed_id: String = ""

func _ready():
	PoolManager.add_pool("spawn_anim", self)
	GameEvents.round_end.connect(on_round_end)

func _exit_tree() -> void:
	_release_claim()

func _release_claim() -> void:
	if _claimed_id != "":
		PoolManager.release_spawn_claim(_claimed_id)
		_claimed_id = ""

func idle_state():
	is_idle = 1
	_release_claim()
	coin_mult = 1
	has_path = false
	is_boss = false
	# 作弊菜单暂停生成时会把本节点置 ALWAYS；归还空闲复位为默认，避免池化后在暂停菜单中仍处理
	process_mode = PROCESS_MODE_INHERIT
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
	_claimed_id = enemy.id
	if is_boss == false:
		self.visible = true
	else:
		self.visible = false
	animation_player.play("new_animation")
	await spawn
	if can_spawn == true:
		spawn_enemy_body(enemy)
	else:
		_release_claim()

func spawn_enemy_body(enemy: EnemyCard):
	var enemy_body = PoolManager.get_pool(enemy.id)
	if enemy_body == null or enemy_body.is_idle == 0:
		enemy_body = enemy.body.instantiate()
		get_tree().get_first_node_in_group("EnemiesRoot").add_child(enemy_body)
	
	# 路线来源：优先关卡显式传入（path_spawn），否则用 EnemyCard.route（数据驱动，所有生成器通用）。
	var route_scene: PackedScene = null
	if has_path == true:
		if path != null:
			route_scene = path
		else:
			route_scene = DEFAULT_ROUTE
			push_error("spawn_anim: has_path but path is null, fallback to DEFAULT_ROUTE (id=%s)" % enemy.id)
	elif enemy.route != null:
		route_scene = enemy.route
	if route_scene != null:
		_setup_path(enemy_body, route_scene, path_value)
	
	enemy_body.global_position = global_position
	# 联机人数缩放：mod 经 ExtensionHooks 注入附加乘数（未注入时保持 1.0，单机零回归）。
	var stat_scale: Dictionary = {}
	if ExtensionHooks.enemy_spawn_stat_scale.is_valid():
		stat_scale = ExtensionHooks.enemy_spawn_stat_scale.call()
	var hp_final: float = hp_mult * float(stat_scale.get("hp", 1.0))
	var damage_final: float = damage_mult * float(stat_scale.get("damage", 1.0))
	enemy_body.stats.max_hp_mult = hp_final
	enemy_body.stats.Enemy_damage_mult = damage_final
	enemy_body.stats.Enemy_bullet_damage_mult = damage_final
	enemy_body.stats.Enemy_coin *= coin_mult
	enemy_body.stats.update_body_ability()
	enemy_body.active_state()
	# 已登记为活跃，释放预占（pending -> active，净值不变）
	_release_claim()
	if enemy_body.body_part != null:
		for i in enemy_body.body_part.size():
			enemy_body.body_part[i].stats.max_hp_mult = hp_final
			enemy_body.body_part[i].stats.update_body_ability()
			enemy_body.body_part[i].active_state()
	ExtensionHooks.notify(ExtensionHooks.on_enemy_spawned, [enemy_body, str(enemy.body.resource_path)])

func on_round_end():
	can_spawn = false
	_release_claim()
	PoolManager.erase_pool("spawn_anim")
	queue_free()

func _setup_path(enemy_body: Node, route_scene: PackedScene, start_value: float) -> void:
	if route_scene == null:
		push_error("spawn_anim: route enemy without route scene (id=%s)" % enemy_body.pool_id)
		return
	var path_ins: Node = enemy_body.get_node_or_null("enemy_path")
	if path_ins == null:
		path_ins = route_scene.instantiate()
		enemy_body.add_child(path_ins)
	if path_ins == null:
		push_error("spawn_anim: failed to instantiate route (id=%s)" % enemy_body.pool_id)
		return
	path_ins.enemy_body = enemy_body
	path_ins.set_start_progress(start_value)
	path_ins.set_body_target()
	path_ins.active_state()
	if enemy_body.get("route_target") == null:
		push_error("spawn_anim: route_target not set after setup (id=%s)" % enemy_body.pool_id)
