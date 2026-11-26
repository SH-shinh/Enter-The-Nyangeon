class_name DanmakuEmitter
extends Node2D

## 弹幕发射器：挂在 Boss / 精英场景下，按 DanmakuSet 轮转招式，
## 按 DanmakuBarrage 的时间轴逐条 cue 发射子弹。
##
## 接入是零侵入的：
## - 敌人死亡/退场/回池 → Enemy.idle_state() 的 _interrupt_weapons() 会调用 stop_firing()
## - Boss 阶段 → 自动连接 boss_phase_changed（没有该信号时按血量比例轮询）
## - 回合结束 → GameEvents.round_end / boss_round_end 停机
##
## 所有子弹统一走 ProjectileSpawner.spawn_core（池 + 联机生成通知 + 伤害口径）。

signal barrage_started(barrage_id: String)
signal barrage_finished(barrage_id: String)
signal budget_rejected(active: int, limit: int)
signal phase_changed(phase: int)

@export var danmaku_set: DanmakuSet
@export var auto_start: bool = true
@export var start_delay: float = 1.0
## 编辑器预览用目标；游戏内留空，走 owner.get_target()。
@export var preview_target: Node2D
@export var debug_log: bool = false

const DEFAULT_BUDGET := 120
const PHASE_POLL_INTERVAL := 0.5

var _active: bool = false
var _delay: float = 0.0
var _barrage: DanmakuBarrage = null
var _schedule: Array[Dictionary] = []
var _shot_index: int = 0
var _barrage_time: float = 0.0
var _cooldown: float = 0.0
var _phase: int = 0
var _phase_override: int = -1
var _phase_poll: float = 0.0
var _cursor: int = 0
var _last_barrage_id: String = ""

var _live_bullets: Array[Node] = []
var _angles: Array[float] = []
var _pool_ids: Dictionary = {}
var _logged: Dictionary = {}

var _cfg_pattern: DanmakuPattern = null
var _cfg_speed: float = 0.0
var _cfg_target: Node2D = null

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if not GameEvents.round_end.is_connected(_on_round_end):
		GameEvents.round_end.connect(_on_round_end)
	if not GameEvents.boss_round_end.is_connected(_on_round_end):
		GameEvents.boss_round_end.connect(_on_round_end)
	var parent := get_parent()
	var candidate := parent
	var guard := 0
	while candidate != null and guard < 4:
		if candidate.has_signal("boss_phase_changed"):
			var callback := Callable(self, "_on_boss_phase_changed")
			if not candidate.is_connected("boss_phase_changed", callback):
				candidate.connect("boss_phase_changed", callback)
			break
		candidate = candidate.get_parent()
		guard += 1


# ---------------- 公共 API ----------------

## 立即开招（忽略 start_delay）。
func begin() -> void:
	if danmaku_set == null:
		return
	_active = true
	_delay = 0.0
	_cooldown = 0.0
	_cursor = 0
	_last_barrage_id = ""
	_abort_barrage()
	_phase = _read_phase()
	if danmaku_set.rng_seed != 0:
		_rng.seed = danmaku_set.rng_seed
	else:
		_rng.randomize()
	if debug_log:
		print("[DanmakuEmitter] begin set=%s phase=%d" % [danmaku_set.id, _phase])


## 停火：取消当前招与所有待发射 cue。已发出的子弹不回收（回合结束由各子弹自理）。
## 会被 Enemy._interrupt_weapons() 自动调用，所以方法名不要改。
func stop_firing() -> void:
	if _barrage != null:
		_abort_barrage()
	_active = false
	_delay = start_delay
	_cooldown = 0.0
	_schedule.clear()
	_shot_index = 0


## 直接播放指定招式（编辑器试播 / Boss 脚本指定招）。
func play_barrage(barrage: DanmakuBarrage) -> void:
	if barrage == null:
		return
	_active = true
	_delay = 0.0
	_abort_barrage()
	_set_current_barrage(barrage)


func set_phase(index: int) -> void:
	_phase_override = index
	if index != _phase:
		_apply_phase(index)


## 回收本发射器发出的子弹。
func clear_bullets() -> void:
	_prune_live()
	for bullet in _live_bullets:
		if bullet != null and is_instance_valid(bullet) and int(bullet.get("is_idle")) == 0:
			if bullet.has_method("bullet_clear"):
				bullet.call("bullet_clear")
	_live_bullets.clear()


func active_bullet_count() -> int:
	_prune_live()
	return _live_bullets.size()


func current_barrage() -> DanmakuBarrage:
	return _barrage


func current_phase() -> int:
	return _phase


## 当前招式的已播放时长（秒，含前摇时可为负；无招式时为 0）。
func elapsed() -> float:
	return _barrage_time if _barrage != null else 0.0


func is_firing() -> bool:
	return _active and _barrage != null


# ---------------- 主循环 ----------------

func _process(delta: float) -> void:
	# 阶段每帧都可轮询：Boss 有 boss_phase_changed，精英/普通敌人靠这里，
	# 不能在「当前招播放中」跳过，否则精英要等一招播完才换阶段。
	if _phase_override < 0 and danmaku_set != null:
		_phase_poll -= delta
		if _phase_poll <= 0.0:
			_phase_poll = PHASE_POLL_INTERVAL
			var polled := _read_phase()
			if polled != _phase:
				_apply_phase(polled)

	if _barrage != null:
		if _parent_is_idle() or not _parent_faction_ok():
			stop_firing()
			return
		_barrage_time += delta
		_fire_due_shots()
		if _barrage_time >= _barrage.effective_duration():
			_finish_barrage()
		return

	if not _active:
		if not auto_start or danmaku_set == null:
			return
		if _parent_is_idle() or not _parent_faction_ok():
			_delay = start_delay
			return
		_delay -= delta
		if _delay <= 0.0:
			begin()
		return

	if _parent_is_idle() or not _parent_faction_ok():
		stop_firing()
		return

	_cooldown -= delta
	if _cooldown <= 0.0:
		_start_next_barrage()


# ---------------- 招式调度 ----------------

func _set_current_barrage(barrage: DanmakuBarrage) -> void:
	_barrage = barrage
	_schedule = DanmakuBarrage.build_shot_schedule(barrage)
	_shot_index = 0
	_barrage_time = -maxf(0.0, barrage.intro_delay)
	_cooldown = 0.0
	_last_barrage_id = barrage.id
	barrage_started.emit(barrage.id)
	if debug_log:
		print("[DanmakuEmitter] barrage=%s shots=%d" % [barrage.barrage_label(), _schedule.size()])


func _finish_barrage() -> void:
	var finished := _barrage
	_barrage = null
	_schedule.clear()
	_shot_index = 0
	_barrage_time = 0.0
	_cooldown = maxf(0.0, finished.cooldown)
	if danmaku_set != null:
		_cooldown += maxf(0.0, danmaku_set.rest_between_barrages)
	barrage_finished.emit(finished.id)


func _abort_barrage() -> void:
	if _barrage == null:
		return
	var aborted := _barrage
	_barrage = null
	_schedule.clear()
	_shot_index = 0
	_barrage_time = 0.0
	barrage_finished.emit(aborted.id)


func _start_next_barrage() -> void:
	if danmaku_set == null:
		stop_firing()
		return
	var candidates := danmaku_set.barrages_for_phase(_phase)
	if candidates.is_empty():
		# 阶段过滤把全部招式排除了：退回全部招式，避免 Boss 站着不动。
		for barrage in danmaku_set.barrages:
			if barrage != null:
				candidates.append(barrage)
	if candidates.is_empty():
		_log_once("empty_set", "[DanmakuEmitter] 招式组为空，停机")
		stop_firing()
		return

	var chosen: DanmakuBarrage = null
	if danmaku_set.loop:
		chosen = _weighted_pick(candidates)
	else:
		if _cursor >= candidates.size():
			stop_firing()
			return
		chosen = candidates[_cursor]
		_cursor += 1
	_set_current_barrage(chosen)


func _weighted_pick(candidates: Array[DanmakuBarrage]) -> DanmakuBarrage:
	var pool := candidates.duplicate()
	if pool.size() > 1 and _last_barrage_id != "":
		var filtered: Array[DanmakuBarrage] = []
		for barrage in pool:
			if barrage.id != _last_barrage_id:
				filtered.append(barrage)
		if not filtered.is_empty():
			pool = filtered
	var total := 0.0
	for barrage in pool:
		total += maxf(0.01, barrage.weight)
	var roll := _rng.randf() * total
	for barrage in pool:
		roll -= maxf(0.01, barrage.weight)
		if roll <= 0.0:
			return barrage
	return pool[pool.size() - 1]


func _fire_due_shots() -> void:
	while _shot_index < _schedule.size():
		var shot: Dictionary = _schedule[_shot_index]
		if float(shot["time"]) > _barrage_time + 0.0001:
			return
		var cue_index := int(shot["cue"])
		if cue_index >= 0 and cue_index < _barrage.cues.size():
			_fire_shot(_barrage.cues[cue_index], int(shot["ordinal"]))
		_shot_index += 1


# ---------------- 单次发射 ----------------

func _fire_shot(cue: DanmakuCue, ordinal: int) -> void:
	if cue == null or cue.pattern == null:
		return
	var pattern := cue.pattern
	var base := _base_angle(pattern)
	if not is_finite(base):
		_log_once("no_target", "[DanmakuEmitter] 无目标，跳过 aim=TARGET 的图案 %s" % pattern.label())
		return

	var spin_deg := pattern.spin_per_volley_deg * float(ordinal)
	base += deg_to_rad(pattern.angle_offset_deg + cue.angle_offset_deg + spin_deg)
	_fill_angles(pattern, base)

	_prune_live()
	var limit := maxi(8, danmaku_set.max_active_bullets if danmaku_set != null else DEFAULT_BUDGET)
	if _live_bullets.size() + _angles.size() > limit:
		budget_rejected.emit(_live_bullets.size(), limit)
		_log_throttled(
			"budget",
			"[DanmakuEmitter] 预算不足，跳过 %s（在飞 %d / 上限 %d）"
			% [pattern.label(), _live_bullets.size(), limit]
		)
		return

	var homing_target := _target_node() if pattern.homing_deg_per_sec != 0.0 else null
	for i in _angles.size():
		var origin := _muzzle_position(pattern)
		if pattern.spread == DanmakuPattern.Spread.PARALLEL and _angles.size() > 1:
			var offset := (float(i) - float(_angles.size() - 1) * 0.5) * pattern.parallel_spacing
			origin += DanmakuMath.perpendicular(base) * offset
		_spawn_bullet(pattern, _angles[i], origin, homing_target)

	if pattern.sfx != "":
		SoundManager.play_sfx(pattern.sfx)
	_spawn_muzzle_fx(pattern, base)


func _fill_angles(pattern: DanmakuPattern, base: float) -> void:
	match pattern.spread:
		DanmakuPattern.Spread.RING:
			DanmakuMath.ring_angles(_angles, pattern.count, base)
		DanmakuPattern.Spread.RANDOM_ARC:
			DanmakuMath.random_arc_angles(
				_angles, pattern.count, deg_to_rad(pattern.arc_deg), base, _rng
			)
		DanmakuPattern.Spread.PARALLEL:
			_angles.clear()
			for i in maxi(1, pattern.count):
				_angles.append(base)
		_:
			DanmakuMath.fan_angles(_angles, pattern.count, deg_to_rad(pattern.arc_deg), base)


func _base_angle(pattern: DanmakuPattern) -> float:
	match pattern.aim:
		DanmakuPattern.Aim.TARGET:
			var target_pos := _target_position()
			if not DanmakuMath.is_finite_vec2(target_pos):
				return NAN
			return (target_pos - global_position).angle()
		DanmakuPattern.Aim.FIXED:
			return deg_to_rad(pattern.fixed_angle_deg)
		DanmakuPattern.Aim.SELF_FACING:
			return global_rotation
		_:
			return _rng.randf_range(-PI, PI)


func _muzzle_position(pattern: DanmakuPattern) -> Vector2:
	return global_position + pattern.muzzle_offset.rotated(global_rotation)


# ---------------- 子弹生成 / 配置 ----------------

func _spawn_bullet(
	pattern: DanmakuPattern, angle: float, origin: Vector2, homing_target: Node2D
) -> void:
	var scene := pattern.bullet_scene
	if scene == null:
		_log_once("no_scene", "[DanmakuEmitter] 图案 %s 未配置 bullet_scene" % pattern.label())
		return
	_cfg_pattern = pattern
	_cfg_speed = DanmakuMath.speed_with_variance(pattern.speed, pattern.speed_random, _rng)
	_cfg_target = homing_target
	ProjectileSpawner.spawn_core(
		scene,
		_pool_id_for(scene),
		"BulletRoot",
		_owner_node(),
		Faction.ENEMY_SIDE,
		origin,
		angle,
		Vector2.ONE * pattern.scale_mult,
		false,
		false,
		true,
		Callable(self, "_configure_bullet"),
		Callable(),
		Callable(self, "_post_bullet")
	)
	_cfg_pattern = null
	_cfg_target = null


func _configure_bullet(node: Node) -> void:
	var pattern := _cfg_pattern
	if node == null or pattern == null:
		return
	var damage := 1.0
	var knockback := 0.0
	var owner_node := _owner_node()
	var stats = owner_node.get("stats") if owner_node != null else null
	if stats != null:
		var base_damage = stats.get("Enemy_bullet_damage")
		if base_damage != null:
			damage = float(base_damage)
		var base_knockback = stats.get("Enemy_Knockback")
		if base_knockback != null:
			knockback = float(base_knockback)
	damage = maxf(1.0, damage * pattern.damage_mult)
	knockback *= pattern.knockback_mult

	node.damage_data = DamageData.fill(node.damage_data, {
		"damage": int(round(damage)),
		"knockback": int(round(knockback)),
		"type": GameTags.BULLET_DAMAGE,
		"source": DamageRouter.source_tag(Faction.ENEMY_SIDE),
	})
	node.set("source_faction", Faction.ENEMY_SIDE)
	node.set("speed", int(round(_cfg_speed)))
	node.set("penetrate", pattern.penetrate)
	node.set("kill_time", maxi(1, int(round(pattern.lifetime * 10.0))))
	if pattern.split_count > 0 and node.get("shoot_bullet_num") != null:
		node.set("shoot_bullet_num", pattern.split_count)
	if node.get("move_speed") != null:
		node.set("move_speed", _cfg_speed)
	if node.get("move_accel") != null:
		node.set("move_accel", pattern.accel)
	if node.get("curvature_deg_per_sec") != null:
		node.set("curvature_deg_per_sec", pattern.curvature_deg_per_sec)
	if node.get("homing_deg_per_sec") != null:
		node.set("homing_deg_per_sec", pattern.homing_deg_per_sec)
	if node.get("homing_duration") != null:
		node.set("homing_duration", pattern.homing_duration)
	if _cfg_target != null and node.has_method("set_homing_target"):
		node.call("set_homing_target", _cfg_target)


func _post_bullet(node: Node) -> void:
	if node == null:
		return
	if node.get("damage_data") != null:
		node.damage_data.source_node = node.get_path()
	_live_bullets.append(node)


func _pool_id_for(scene: PackedScene) -> String:
	if _pool_ids.has(scene):
		return String(_pool_ids[scene])
	var pool_id := ""
	var probe := scene.instantiate()
	if probe != null:
		var value = probe.get("pool_id")
		if value is String:
			pool_id = value
		probe.free()
	_pool_ids[scene] = pool_id
	return pool_id


func _spawn_muzzle_fx(pattern: DanmakuPattern, angle: float) -> void:
	if pattern.muzzle_fx == null:
		return
	if not PoolManager.fx_allowed(&"muzzle_flash"):
		return
	var instance := pattern.muzzle_fx.instantiate()
	if instance == null:
		return
	var layer := get_tree().get_first_node_in_group("SELayer")
	if layer != null:
		layer.add_child(instance)
	else:
		add_child(instance)
	if instance is Node2D:
		(instance as Node2D).global_position = _muzzle_position(pattern)
		(instance as Node2D).global_rotation = angle
	if instance.has_method("active_state"):
		instance.call("active_state")


# ---------------- 目标 / 父节点 ----------------

func _owner_node() -> Node:
	# 发射器可能挂在装饰节点/标记下，向上找最近的「实体」：有 stats 或 is_idle。
	var node := get_parent()
	var guard := 0
	while node != null and guard < 4:
		if node.get("stats") != null or node.get("is_idle") != null:
			return node
		node = node.get_parent()
		guard += 1
	var parent := get_parent()
	return parent if parent != null else self


func _target_node() -> Node2D:
	if preview_target != null and is_instance_valid(preview_target):
		return preview_target
	var owner_node := _owner_node()
	if owner_node != null and owner_node.has_method("get_target"):
		var target = owner_node.call("get_target")
		if target is Node2D:
			return target as Node2D
	if is_inside_tree():
		var player := get_tree().get_first_node_in_group("Player")
		if player is Node2D:
			return player as Node2D
	return null


func _target_position() -> Vector2:
	var target := _target_node()
	if target != null:
		return target.global_position
	var owner_node := _owner_node()
	if owner_node != null and owner_node.has_method("get_target_position"):
		var position = owner_node.call("get_target_position")
		if position is Vector2 and DanmakuMath.is_finite_vec2(position):
			return position
	return Vector2.INF


func _parent_is_idle() -> bool:
	var owner_node := _owner_node()
	if owner_node == null:
		return false
	var value = owner_node.get("is_idle")
	return value != null and int(value) == 1


func _parent_faction_ok() -> bool:
	var owner_node := _owner_node()
	if owner_node == null:
		return true
	var value = owner_node.get("faction")
	if value == null:
		return true
	return int(value) == Faction.ENEMY_SIDE


func _read_phase() -> int:
	if _phase_override >= 0:
		return _phase_override
	if danmaku_set == null:
		return 0
	var owner_node := _owner_node()
	var stats = owner_node.get("stats") if owner_node != null else null
	if stats == null:
		return 0
	var max_hp: float = float(stats.get("max_hp")) if stats.get("max_hp") != null else 0.0
	if max_hp <= 0.0:
		return 0
	var hp: float = float(stats.get("hp")) if stats.get("hp") != null else max_hp
	return DanmakuMath.phase_for_ratio(clampf(hp / max_hp, 0.0, 1.0), danmaku_set.phase_hp_thresholds)


func _apply_phase(index: int) -> void:
	var changed := index != _phase
	_phase = index
	_phase_poll = PHASE_POLL_INTERVAL
	if changed:
		phase_changed.emit(index)
	if danmaku_set != null and danmaku_set.interrupt_on_phase_change and _barrage != null:
		if danmaku_set.clear_bullets_on_phase_change:
			clear_bullets()
		_abort_barrage()
		_cooldown = 0.0
	if debug_log:
		print("[DanmakuEmitter] phase=%d" % index)


func _on_boss_phase_changed(phase: int) -> void:
	set_phase(phase)


func _on_round_end() -> void:
	stop_firing()


# ---------------- 记账 / 日志 ----------------

func _prune_live() -> void:
	for i in range(_live_bullets.size() - 1, -1, -1):
		var bullet := _live_bullets[i]
		if bullet == null or not is_instance_valid(bullet) or int(bullet.get("is_idle")) == 1:
			_live_bullets.remove_at(i)


func _log_once(key: String, message: String) -> void:
	if _logged.has(key):
		return
	_logged[key] = true
	push_warning(message)


func _log_throttled(key: String, message: String) -> void:
	var now := Time.get_ticks_msec()
	var last := int(_logged.get(key, -100000))
	if now - last < 2000:
		return
	_logged[key] = now
	if debug_log:
		push_warning(message)
