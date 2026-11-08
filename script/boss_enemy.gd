class_name BossEnemy
extends Enemy

# Boss 实体基类：只负责自己的血量、阶段、动画和奖励内容。 parse-check
# 镜头/暂停/回合结束由 BossRoundController + BossCinematic 负责，Boss 不直接写 paused。
signal boss_enter_finished
signal boss_death_finished
signal boss_phase_changed(phase: int)
signal boss_phase_anim_finished(phase: int)
signal boss_exit_finished
signal boss_defeated

@export var boss_card: BossCard
# BossRoundEntry.reward_scene 的运行时覆盖（不修改共享资源）。
var reward_scene_override: PackedScene

var _boss_dead: bool = false
var _enter_started: bool = false
var _death_started: bool = false
var _exit_started: bool = false
var _phase_index: int = 0
var _phases: Array[BossPhase] = []
var _phase_invuln_generation: int = 0

func _ready() -> void:
	super._ready()
	add_to_group("Enemy")
	add_to_group("BOSS")

func active_state():
	super.active_state()
	_boss_dead = false
	_enter_started = false
	_death_started = false
	_exit_started = false
	_phase_index = 0
	_phase_invuln_generation += 1
	_build_phases()
	_connect_phase_signal()
	# 旧式波次（非 BossRoundController 编排）没有控制器负责入场，这里只播动画，不做镜头/暂停。
	if boss_card != null and not has_meta("boss_managed"):
		play_enter_anim()

func idle_state():
	super.idle_state()
	_boss_dead = false
	_enter_started = false
	_death_started = false
	_exit_started = false
	_phase_index = 0
	_phase_invuln_generation += 1

# Boss 的默认金币掉落必须由 drop_rewards() 接管，避免 Enemy 基类先掉一次普通金币。
func _coin_drops():
	pass

func on_dead():
	if _boss_dead:
		return
	_boss_dead = true
	hurt_box_shape_2d.set_deferred("disabled", true)
	collision_shape_2d.set_deferred("disabled", true)
	_interrupt_weapons()
	if state_machine != null:
		state_machine.set_physics_process(false)
	set_physics_process(false)
	if enemy_buff_manager != null:
		enemy_buff_manager.clear_all_buff()
	GameEvents.emit_enemy_dead_position(global_position)
	boss_defeated.emit()
	GameEvents.emit_boss_defeated(self)
	ExtensionHooks.notify_named("on_boss_defeated", [self])

func play_enter_anim() -> void:
	if _enter_started:
		return
	_enter_started = true
	var ap := _get_anim_player(boss_card.enter_anim_player_path if boss_card != null else NodePath())
	var anim_name := boss_card.enter_anim_name if boss_card != null else &""
	_play_anim_and_emit(ap, anim_name, boss_enter_finished)

func play_death_anim() -> void:
	if _death_started:
		return
	_death_started = true
	var ap := _get_anim_player(boss_card.death_anim_player_path if boss_card != null else NodePath())
	var anim_name := boss_card.death_anim_name if boss_card != null else &""
	_play_anim_and_emit(ap, anim_name, boss_death_finished)

func play_exit_anim() -> void:
	if _exit_started:
		return
	_exit_started = true
	if health_component != null:
		health_component.is_invincible = true
	if hurt_box_shape_2d != null:
		hurt_box_shape_2d.set_deferred("disabled", true)
	if collision_shape_2d != null:
		collision_shape_2d.set_deferred("disabled", true)
	_interrupt_weapons()
	set_combat_enabled(false)

	if boss_card == null:
		_emit_exit_finished()
		return
	var ap := _get_anim_player(boss_card.enter_anim_player_path)
	var anim_name := boss_card.enter_anim_name
	if ap == null or anim_name == &"" or not ap.has_animation(anim_name):
		_emit_exit_finished()
		return

	var source := ap.get_animation(anim_name)
	if source == null:
		_emit_exit_finished()
		return
	var exit_anim := source.duplicate(true) as Animation
	for i in exit_anim.get_track_count():
		if exit_anim.track_get_type(i) == Animation.TYPE_METHOD:
			exit_anim.track_set_enabled(i, false)

	var library_name := "__boss_exit_%d" % get_instance_id()
	var library := AnimationLibrary.new()
	library.add_animation(&"exit", exit_anim)
	if ap.add_animation_library(library_name, library) != OK:
		_emit_exit_finished()
		return
	ap.process_mode = Node.PROCESS_MODE_ALWAYS
	ap.play_backwards(StringName("%s/exit" % library_name))
	_run_exit_anim(ap, library_name)

func _emit_exit_finished() -> void:
	call_deferred("_emit_exit_signal")

func _emit_exit_signal() -> void:
	boss_exit_finished.emit()

func _run_exit_anim(ap: AnimationPlayer, library_name: StringName) -> void:
	while true:
		var finished_name: StringName = await ap.animation_finished
		if String(finished_name).ends_with("/exit"):
			break
	if ap.has_animation_library(library_name):
		ap.remove_animation_library(library_name)
	boss_exit_finished.emit()

func play_phase_anim(phase: int) -> void:
	var phase_data := get_phase_data(phase)
	if phase_data == null or phase_data.enter_anim_name == &"":
		_emit_phase_finished(phase)
		return
	var player_path := phase_data.phase_anim_player_path
	if player_path.is_empty() and boss_card != null:
		player_path = boss_card.enter_anim_player_path
	var ap := _get_anim_player(player_path)
	if ap == null:
		_emit_phase_finished(phase)
		return
	ap.process_mode = Node.PROCESS_MODE_ALWAYS
	ap.play(phase_data.enter_anim_name)
	_run_phase_anim(ap, phase_data.enter_anim_name, phase)

func get_phase_data(phase: int) -> BossPhase:
	if phase < 0 or phase >= _phases.size():
		return null
	return _phases[phase]

func _emit_phase_finished(phase: int) -> void:
	call_deferred("_emit_phase_signal", phase)

func _emit_phase_signal(phase: int) -> void:
	boss_phase_anim_finished.emit(phase)

func _run_phase_anim(ap: AnimationPlayer, anim_name: StringName, phase: int) -> void:
	while true:
		var finished_name: StringName = await ap.animation_finished
		if finished_name == anim_name:
			break
	boss_phase_anim_finished.emit(phase)

func _apply_phase_effects(phase_data: BossPhase) -> void:
	if phase_data == null:
		return
	if phase_data.buff != null and enemy_buff_manager != null:
		var value := [maxi(1, phase_data.buff_layer), phase_data.buff_value, phase_data.buff_duration]
		enemy_buff_manager.apply_buff(phase_data.buff, value)
	if phase_data.invulnerable_duration > 0.0 and health_component != null:
		_phase_invuln_generation += 1
		var generation := _phase_invuln_generation
		var was_invincible: bool = health_component.is_invincible
		health_component.is_invincible = true
		await get_tree().create_timer(phase_data.invulnerable_duration, true, false, true).timeout
		if generation == _phase_invuln_generation and is_instance_valid(health_component):
			health_component.is_invincible = was_invincible

func play_fever_anim() -> void:
	pass

func play_escape_anim() -> void:
	if boss_card == null or boss_card.escape_anim_name == &"":
		return
	var ap := _get_anim_player(boss_card.enter_anim_player_path)
	if ap == null:
		return
	ap.process_mode = Node.PROCESS_MODE_ALWAYS
	ap.play(boss_card.escape_anim_name)

func get_camera_marker() -> Marker2D:
	if boss_card == null or boss_card.camera_marker_path.is_empty():
		return null
	return get_node_or_null(boss_card.camera_marker_path) as Marker2D

func get_hp_stats() -> EnemyStats:
	return stats

func get_boss_name() -> String:
	if boss_card == null:
		return name
	if boss_card.boss_name_key != "":
		return tr(boss_card.boss_name_key)
	if boss_card.boss_name != "":
		return boss_card.boss_name
	return name

func get_boss_parts() -> Array:
	return body_part

func drop_rewards() -> void:
	var reward: PackedScene = reward_scene_override
	if reward == null and boss_card != null:
		reward = boss_card.reward_scene
	if reward != null:
		var reward_node := reward.instantiate()
		if reward_node is Node2D:
			reward_node.global_position = global_position
		if boss_card.reward_coin_count > 0 and reward_node.get("coin_count") != null:
			reward_node.set("coin_count", boss_card.reward_coin_count)
		if boss_card.reward_coin_quantity > 0 and reward_node.get("coin_quantity") != null:
			reward_node.set("coin_quantity", boss_card.reward_coin_quantity)
		var root := get_tree().get_first_node_in_group("CoinRoot")
		if root != null:
			root.add_child(reward_node)
		else:
			add_child(reward_node)
		if reward_node.has_method("add_coin"):
			reward_node.call_deferred("add_coin")
		return
	# 未配置专属奖励时回退普通金币掉落。
	if boss_card == null or boss_card.reward_scene == null:
		super._coin_drops()

func despawn_after_death() -> void:
	if pool_id != "":
		PoolManager.erase_pool(pool_id)
	queue_free()

func despawn_immediate() -> void:
	despawn_after_death()

func set_combat_enabled(enabled: bool) -> void:
	set_physics_process(enabled)
	if state_machine != null:
		state_machine.set_physics_process(enabled)

func on_round_timeout(_profile: BossRoundProfile) -> StringName:
	return &"rage"

func _get_anim_player(path: NodePath) -> AnimationPlayer:
	if path.is_empty():
		return null
	return get_node_or_null(path) as AnimationPlayer

func _play_anim_and_emit(ap: AnimationPlayer, anim_name: StringName, sig: Signal) -> void:
	if ap == null or anim_name == &"":
		# 延迟到下一帧，确保 BossCinematic 先 connect 再收到信号。
		call_deferred("_emit_boss_signal", sig)
		return
	ap.process_mode = Node.PROCESS_MODE_ALWAYS
	ap.play(anim_name)
	_run_anim_and_emit(ap, anim_name, sig)

func _emit_boss_signal(sig: Signal) -> void:
	sig.emit()

func _run_anim_and_emit(ap: AnimationPlayer, anim_name: StringName, sig: Signal) -> void:
	while true:
		var finished_name: StringName = await ap.animation_finished
		if finished_name == anim_name:
			break
	sig.emit()

func _build_phases() -> void:
	_phases.clear()
	if boss_card == null:
		return
	for p in boss_card.phases:
		if p != null:
			_phases.append(p)
	_phases.sort_custom(func(a, b): return a.hp_ratio > b.hp_ratio)

func _connect_phase_signal() -> void:
	if stats == null:
		return
	if not stats.hp_changed.is_connected(_on_boss_hp_changed):
		stats.hp_changed.connect(_on_boss_hp_changed)

func _on_boss_hp_changed() -> void:
	if _boss_dead or stats == null or stats.max_hp <= 0 or _phases.is_empty():
		return
	var ratio := float(stats.hp) / float(stats.max_hp)
	while _phase_index < _phases.size() and ratio <= _phases[_phase_index].hp_ratio:
		_phase_index += 1
		var phase_data := _phases[_phase_index - 1]
		_apply_phase_effects(phase_data)
		boss_phase_changed.emit(_phase_index)
		GameEvents.emit_boss_phase_changed(self, _phase_index)
