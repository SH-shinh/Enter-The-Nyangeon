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
# 普通回合中途乱入：血量减半、奖励削减，且不触发 Boss 回合/运镜。
var is_intruder: bool = false
# true = 由 BossRoundController/BossSpawner 编排（入场/死亡演出由控制器负责）
var controller_managed: bool = false

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
	reset_physics_interpolation()
	is_idle = 1
	_release_claim()
	coin_mult = 1
	has_path = false
	is_boss = false
	is_intruder = false
	controller_managed = false
	remove_from_group("BossIntruder")
	# 作弊菜单暂停生成时会把本节点置 ALWAYS；归还空闲复位为默认，避免池化后在暂停菜单中仍处理
	process_mode = PROCESS_MODE_INHERIT
	self.visible = false
	self.global_position = Vector2.ZERO

func active_state():
	reset_physics_interpolation()
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
		# 中止生成：同步退出乱入索引，避免残留节点让 has_active_boss_intruder() 误报。
		remove_from_group("BossIntruder")
		_release_claim()

func spawn_enemy_body(enemy: EnemyCard):
	var enemy_body = PoolManager.get_pool(enemy.id)
	if enemy_body == null or enemy_body.is_idle == 0:
		enemy_body = enemy.body.instantiate()
		get_tree().get_first_node_in_group("EnemiesRoot").add_child(enemy_body)
	
	if enemy is BossCard:
		if enemy_body is BossEnemy:
			enemy_body.boss_card = enemy
			enemy_body.set_meta("boss_managed", controller_managed)
		else:
			push_warning("[spawn_anim] BossCard %s 的 body 根节点未继承 BossEnemy" % enemy.id)

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

	# 难度分层走位：Boss / 测试房 / 路线型敌人不注入，走位保持原样。
	if enemy_body.has_method("set_ai_profile"):
		var profile := _resolve_ai_profile(enemy, enemy_body)
		enemy_body.set_ai_profile(profile)
		_log_ai_profile(profile)

	enemy_body.global_position = global_position
	if not is_boss and enemy_body.has_method("set_ai_profile") and enemy_body.get("route_target") == null:
		# 非 Boss / 非路线型 AI 敌人：生成点若落在壁垒/障碍格或紧贴障碍，挪到最近安全点。
		if EnemyNavField.ensure_topology() and not EnemyNavField.is_body_safe(enemy_body.global_position, 1):
			var safe := EnemyNavField.nearest_body_safe_point(enemy_body.global_position, 1)
			if safe.is_finite():
				enemy_body.global_position = safe
	if is_intruder:
		enemy_body.add_to_group("BossIntruder")
		enemy_body.set_meta("boss_intruder", true)
		# 实体已落地，后续由实体自身代表乱入；spawn_anim 不再算 pending。
		remove_from_group("BossIntruder")
	else:
		if enemy_body.has_meta("boss_intruder"):
			enemy_body.remove_meta("boss_intruder")
		enemy_body.remove_from_group("BossIntruder")
	# 联机人数缩放：mod 经 ExtensionHooks 注入附加乘数（未注入时保持 1.0，单机零回归）。
	var stat_scale: Dictionary = {}
	if ExtensionHooks.enemy_spawn_stat_scale.is_valid():
		stat_scale = ExtensionHooks.enemy_spawn_stat_scale.call()
	var hp_final: float = hp_mult * float(stat_scale.get("hp", 1.0))
	if is_intruder:
		hp_final *= 0.5
	var damage_final: float = damage_mult * float(stat_scale.get("damage", 1.0))
	enemy_body.stats.max_hp_mult = hp_final
	enemy_body.stats.Enemy_damage_mult = damage_final
	enemy_body.stats.Enemy_bullet_damage_mult = damage_final
	enemy_body.stats.Enemy_coin *= coin_mult
	enemy_body.stats.update_body_ability()
	var chip_manager := get_tree().get_first_node_in_group("ChipManager")
	if chip_manager != null and chip_manager.has_method("apply_to_enemy"):
		if chip_manager.apply_to_enemy(enemy_body, enemy, is_boss):
			enemy_body.stats.update_body_ability()
	enemy_body.active_state()
	# 已登记为活跃，释放预占（pending -> active，净值不变）
	_release_claim()
	if enemy_body.body_part != null:
		for i in enemy_body.body_part.size():
			enemy_body.body_part[i].stats.max_hp_mult = hp_final
			enemy_body.body_part[i].stats.update_body_ability()
			enemy_body.body_part[i].active_state()
	ExtensionHooks.notify_named("on_enemy_spawned", [enemy_body, str(enemy.body.resource_path)])
	if enemy is BossCard and enemy_body is BossEnemy:
		GameEvents.emit_boss_spawned(enemy_body, enemy)
		ExtensionHooks.notify_named("on_boss_spawned", [enemy_body, enemy])

func on_round_end():
	can_spawn = false
	_release_claim()
	_ai_profile_logged = false
	PoolManager.erase_pool("spawn_anim")
	queue_free()

# 敌人 AI 的兜底 profile：正式战斗默认就带 AI，难度只决定强度。
# （历史上这里返回 null 表示「关闭」，导致 NORMAL/未设难度的流程完全没有走位。）
const DEFAULT_AI_PROFILE: EnemyAIProfile = preload("res://resources/enemy_ai/normal.tres")

static var _ai_profile_logged: bool = false

# 难度分层走位参数：Boss / 测试房 / 路线型敌人返回 null（保持改造前的走位）。
func _resolve_ai_profile(card: EnemyCard, body: Node) -> EnemyAIProfile:
	if is_boss or card is BossCard:
		return null
	if PlayerData.on_test_room:
		return null
	if card != null and card.route != null:
		return null
	if body != null and body.get("route_target") != null:
		return null
	var level := PlayerData.current_level
	if level != null and level.enemy_ai != null:
		return level.enemy_ai
	return DEFAULT_AI_PROFILE

# dev_mode 下每回合打印一次，避免「以为在测新 AI、其实 profile 是 null」。
func _log_ai_profile(profile: EnemyAIProfile) -> void:
	if not Game.dev_mode or _ai_profile_logged:
		return
	_ai_profile_logged = true
	var level_id: String = PlayerData.level_id if PlayerData.current_level != null else "<none>"
	var profile_id: String = profile.id if profile != null else "<off>"
	print("[ETNAI] round=%d level=%s profile=%s" % [PlayerData.now_round, level_id, profile_id])

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
