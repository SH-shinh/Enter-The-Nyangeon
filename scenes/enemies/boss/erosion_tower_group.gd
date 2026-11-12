extends Node2D

@export var stats: EnemyStats
@export var tower_1: Node
@export var tower_2: Node
@export var tower_3: Node
# 出招序列（按数组顺序循环；每招用 phases 位掩码限定生效阶段）
@export var attack_sequence: Array[TowerAttackStep] = []
# 阶段血量阈值（降序，`_ready` 会自动排序）：ratio < 阈值[0] → 阶段 1；ratio < 阈值[1] → 阶段 2 …
@export var phase_hp_thresholds: PackedFloat32Array = PackedFloat32Array([0.5])
# HP 跨阶段时是否立即收招（false = 等本招窗口结束后再生效）
@export var interrupt_on_phase_change: bool = true

@onready var camera_marker: Marker2D = $boss_enter/CameraMarker
@onready var coins: PackedScene = preload("res://scenes/item/coin_box.tscn")
@onready var pyroxenes: PackedScene = preload("res://scenes/item/pyroxenes.tscn")
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var tower_group: Array[Node]
var body_part: Array[Node]

# 出招调度状态（单位：GameEvents.global_time_count 的 0.1s tick）
var _started: bool = false
var _step_index: int = -1
var _ticks_left: int = 0
var _in_window: bool = false
var _current_phase: int = -1

# 防止 is_dead 与状态机 DEAD 双路触发导致重复结算
var _dead_started: bool = false
var _intruder_escaping: bool = false

# 联机：塔组可视动画态广播（host 发、镜像回放）
var _net_visual_replaying: bool = false

const LASER_TOWER_TYPE: int = 1
const PHASE_FLAG_MAX: int = 4
# 乱入退场：倒放入场动画的时长基准 + 兜底余量；退场完成不能依赖 animation_finished。
const ESCAPE_ANIM: StringName = &"enter_anim"
const ESCAPE_ANIM_FALLBACK_SEC: float = 3.0
const ESCAPE_ANIM_MARGIN_SEC: float = 0.15
# 乱入 FEVER 内击杀：等待死亡动画的上限，防止信号丢失把结算永久挂起。
const DEATH_WAIT_TIMEOUT_SEC: float = 6.0
# 场景未配置 attack_sequence 时的内置默认序列（与 resources/boss/tower_attack/*.tres 同源）
const DEFAULT_STEPS: Array = [
	preload("res://resources/boss/tower_attack/phase1_laser_summon.tres"),
	preload("res://resources/boss/tower_attack/phase1_bullet_summon.tres"),
	preload("res://resources/boss/tower_attack/phase2_all.tres"),
]

func _ready() -> void:
	GameEvents.boss_event.connect(_on_network_boss_event)
	_sort_phase_thresholds()

# 阈值必须降序参与阶段换算；编辑器里填反了也能工作。
func _sort_phase_thresholds() -> void:
	var sorted_values: Array = []
	for t in phase_hp_thresholds:
		sorted_values.append(float(t))
	sorted_values.sort()
	sorted_values.reverse()
	var rebuilt := PackedFloat32Array()
	for t in sorted_values:
		rebuilt.append(float(t))
	phase_hp_thresholds = rebuilt

func _net_boss_visual(fn_name: String) -> void:
	if _net_visual_replaying:
		return
	GameEvents.emit_boss_event("erosion_tower_group_visual", {"fn": fn_name})

func _on_network_boss_event(event_name: String, data: Dictionary) -> void:
	if not has_meta("network_remote_enemy"):
		return
	if event_name != "erosion_tower_group_visual":
		return
	var fn: String = str(data.get("fn", ""))
	if fn == "" or not has_method(fn):
		return
	_net_visual_replaying = true
	call(fn)
	_net_visual_replaying = false

# ---------------- 出招序列（固定周期 + 阶段筛选，结构对齐 Goliath） ----------------
# 说明：阶段切换只决定「下一招从哪开始」，不打断窗口（除非 interrupt_on_phase_change）。
# 窗口下限只统计真正会开火的激光塔（tower_type==1）——三座塔都继承 laser_launcher，
# 若按 launcher_pool_1 非空判断会把弹幕/召唤招也拖成 18 秒（旧实现的隐式行为）。

func phase_for_ratio(ratio: float, thresholds: PackedFloat32Array) -> int:
	var phase: int = 0
	for t in thresholds:
		if ratio < float(t):
			phase += 1
	return clampi(phase, 0, PHASE_FLAG_MAX - 1)

func step_matches(step: TowerAttackStep, phase: int, alive_types: Dictionary) -> bool:
	if step == null or step.tower_types.is_empty():
		return false
	var bit: int = 1 << clampi(phase, 0, PHASE_FLAG_MAX - 1)
	if (step.phases & bit) == 0:
		return false
	for type_id in step.tower_types:
		if bool(alive_types.get(int(type_id), false)):
			return true
	return false

func next_eligible_index(steps: Array, start: int, phase: int, alive_types: Dictionary) -> int:
	var count: int = steps.size()
	if count <= 0:
		return -1
	var index: int = start % count
	if index < 0:
		index += count
	for _scan in count:
		var step: TowerAttackStep = steps[index]
		if step_matches(step, phase, alive_types):
			return index
		index = (index + 1) % count
	return -1

func attack_state():
	_reset_schedule()
	if attack_sequence.is_empty():
		push_warning("erosion_tower_group: attack_sequence 为空，使用内置默认序列")
		for step in DEFAULT_STEPS:
			attack_sequence.append(step)
	_started = true
	_current_phase = _phase_for_hp()
	_step_index = -1
	_advance_step()

func _reset_schedule() -> void:
	_started = false
	_step_index = -1
	_ticks_left = 0
	_in_window = false
	_current_phase = -1
	stop_shoot()

func time_count():
	if _intruder_escaping or _dead_started or not _started:
		return
	if _in_window:
		_ticks_left -= 1
		if _ticks_left <= 0:
			_end_window()
		return
	if _ticks_left > 0:
		_ticks_left -= 1
		if _ticks_left <= 0:
			_advance_step()
		return
	_advance_step()

func _advance_step() -> void:
	var phase: int = _phase_for_hp()
	var start: int = _step_index + 1
	if phase != _current_phase:
		_current_phase = phase
		start = 0
	var index: int = next_eligible_index(attack_sequence, start, phase, _alive_type_map())
	if index < 0:
		# 没有可用招式（目标塔全灭/序列与阶段不匹配）：保持静止直到结束
		stop_shoot()
		_in_window = false
		_ticks_left = 0
		return
	_step_index = index
	_begin_step(attack_sequence[index])

func _begin_step(step: TowerAttackStep) -> void:
	stop_shoot()
	var towers: Array[Node] = []
	for tower in tower_group:
		if tower == null or not is_instance_valid(tower):
			continue
		if not step.tower_types.has(int(tower.tower_type)):
			continue
		if not _is_tower_alive(tower):
			continue
		tower.can_shoot = true
		towers.append(tower)
	_ticks_left = _effective_window(step, towers)
	_in_window = true

func _end_window() -> void:
	stop_shoot()
	_in_window = false
	_ticks_left = 0
	if _step_index >= 0 and _step_index < attack_sequence.size():
		_ticks_left = maxi(0, attack_sequence[_step_index].gap_ticks)

# 基准窗口与激光完整时长取大：避免 stop_shoot 在出光中途截断。
func _effective_window(step: TowerAttackStep, towers: Array[Node]) -> int:
	var total: int = maxi(1, step.window_ticks)
	for tower in towers:
		if int(tower.tower_type) != LASER_TOWER_TYPE:
			continue
		var launchers = tower.launcher_pool_1
		if launchers == null:
			continue
		for launcher in launchers:
			if launcher != null and is_instance_valid(launcher):
				total = maxi(total, int(launcher.total_active_ticks()))
	return total

func _phase_for_hp() -> int:
	if stats == null or stats.max_hp <= 0:
		return 0
	return phase_for_ratio(float(stats.hp) / float(stats.max_hp), phase_hp_thresholds)

func _alive_type_map() -> Dictionary:
	var map: Dictionary = {}
	for tower in tower_group:
		if tower == null or not is_instance_valid(tower):
			continue
		var type_id: int = int(tower.tower_type)
		map[type_id] = bool(map.get(type_id, false)) or _is_tower_alive(tower)
	return map

func _is_tower_alive(tower: Node) -> bool:
	if tower == null or not is_instance_valid(tower):
		return false
	if int(tower.is_idle) == 1:
		return false
	var tower_stats = tower.stats
	if tower_stats == null:
		return false
	return int(tower_stats.hp) > 0

func _on_hp_changed() -> void:
	if _dead_started or _intruder_escaping or not _started:
		return
	var phase: int = _phase_for_hp()
	if phase == _current_phase:
		return
	if not interrupt_on_phase_change:
		return
	# 立即收招，下一次 tick 从新阶段第一招开始
	_current_phase = phase
	stop_shoot()
	_in_window = false
	_step_index = -1
	_ticks_left = 0

func active_state():
	reset_physics_interpolation()
	_dead_started = false
	_intruder_escaping = false
	_reset_schedule()
	await get_tree().create_timer(0.1).timeout
	update_tower()
	count_max_hp()
	boss_enter_anim()
	if not stats.hp_changed.is_connected(_on_hp_changed):
		stats.hp_changed.connect(_on_hp_changed)
	if not GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)

func stop_shoot():
	for i in tower_group:
		if i != null and is_instance_valid(i):
			i.can_shoot = false

func update_tower():
	tower_group = [tower_1, tower_2, tower_3]
	for i in tower_group:
		if not i.stats.hp_changed.is_connected(count_now_hp):
			i.stats.hp_changed.connect(count_now_hp)
		i.stats.max_hp_mult = stats.max_hp_mult
		i.stats.Enemy_damage_mult = stats.Enemy_damage_mult
		i.stats.Enemy_bullet_damage_mult = stats.Enemy_bullet_damage_mult
		i.stats.update_body_ability()
		i.active_state()
	# 重新入场前先清免疫，随后 boss_enter_anim 会按演出阶段重新开启。
	_set_towers_invincible(false)

# 入场/撤退演出期间免疫一切伤害：统一走 HealthComponent.is_invincible 闸门
# （覆盖子弹/爆炸/近战/DOT/火场/pending extra/一击必杀）。
# 联机镜像（network_remote_enemy）不设，避免影响客机由快照驱动的 HP 与伤害预测。
func _set_towers_invincible(value: bool) -> void:
	if has_meta("network_remote_enemy"):
		return
	for tower in tower_group:
		if tower == null or not is_instance_valid(tower):
			continue
		var health = tower.get("health_component")
		if health != null:
			health.is_invincible = value

func boss_dead(tower: ErosionTower):
	# 聚合血量依赖子塔 hp_changed 时序；结算前强制重算，且只结算一次
	if _intruder_escaping:
		# 撤退优先：退场已接管收尾（退场期间免疫伤害）。这里的早退是 load-bearing，
		# 防止死亡路径的 boss_death_anim / _coin_drops 在退场 await 期间自释放。
		return
	count_now_hp()
	if _dead_started:
		return
	if stats.hp <= 0:
		_dead_started = true
		if not has_meta("boss_intruder"):
			GameEvents.emit_boss_round_end()
		boss_death_anim(tower)


func boss_death_anim(tower: Node = null) -> void:
	_net_boss_visual("boss_death_anim")
	# 死亡演出期间保持子塔动画常开（黑幕暂停下仍播）
	for i in tower_group:
		if i != null and is_instance_valid(i):
			i.animation_player_1.process_mode = Node.PROCESS_MODE_ALWAYS
			i.animation_player_2.process_mode = Node.PROCESS_MODE_ALWAYS
			i.animation_player_3.process_mode = Node.PROCESS_MODE_ALWAYS
	animation_player.play("death_anim")
	# 镜像只播动画，不做相机/暂停演出；塔组由死亡动画 method 轨 _coin_drops 自释放
	if has_meta("network_remote_enemy"):
		return
	# 乱入：死亡动画照常播放，但不运镜、不暂停；死亡位置立即上报。
	if has_meta("boss_intruder"):
		# 乱入死亡无运镜：显式隐藏血条。self.visible=false 隐藏不了 CanvasLayer。
		var hp_ui := get_node_or_null("BossHP")
		if hp_ui != null and hp_ui.has_method("game_ui_visible"):
			hp_ui.game_ui_visible(false)
		GameEvents.emit_enemy_dead_position(self.global_position)
		await animation_player.animation_finished
		self.visible = false
		for i in tower_group:
			i.idle_state.call_deferred()
		return
	if tower != null:
		camera_marker.position = tower.position + Vector2(0, -64)
	GameEvents.emit_camera_move(camera_marker, true)
	GameEvents.emit_ui_visible(false)
	GameEvents.emit_pause_lock(true)
	get_tree().paused = true
	await animation_player.animation_finished
	GameEvents.emit_camera_reset()
	GameEvents.emit_ui_visible(true)
	get_tree().paused = false
	GameEvents.emit_pause_lock(false)
	GameEvents.emit_enemy_dead_position(self.global_position)
	self.visible = false
	for i in tower_group:
		i.idle_state.call_deferred()

# 乱入超时：三塔倒放入场动画后消失，不运镜、不暂停、不结算奖励。
# ⚠️ 退场完成不能 await 塔的 animation_finished：塔状态机在下一物理帧从 SHOOTING 切到 IDLE 时
# 会用循环的 "idle" 覆盖同一个 animation_player_3，信号永不发出 → FEVER 结算永久挂起、回合卡死。
# 这里先冻结状态机，再按入场动画长度做固定时长等待，退场必定有界返回。
func boss_intruder_escape() -> void:
	if _intruder_escaping or _dead_started:
		return
	_intruder_escaping = true
	stop_shoot()
	# 退场期间免疫一切伤害：避免同帧命中/DOT 在退场中打死塔、与收尾流程竞争。
	_set_towers_invincible(true)
	var boss_hp_ui := get_node_or_null("BossHP")
	if boss_hp_ui != null and boss_hp_ui.has_method("game_ui_visible"):
		boss_hp_ui.game_ui_visible(false)
	var wait_tower: Node = null
	for tower in tower_group:
		if tower == null or not is_instance_valid(tower):
			continue
		# 先冻结驱动源：否则 stop_shoot 之后状态机会走 idle_anim() 覆盖退场动画。
		if tower.state_machine != null:
			tower.state_machine.set_physics_process(false)
		# 显式发出塔的 stop_shoot（原由状态机 SHOOTING→IDLE 时发出），停掉激光/弹幕。
		tower.stop_shoot.emit()
		tower.can_shoot = false
		tower.can_defense = false
		tower.collision_shape_2d.set_deferred("disabled", true)
		tower.hurt_box_shape_2d.set_deferred("disabled", true)
		tower.set_physics_process(false)
		tower.animation_player_1.process_mode = Node.PROCESS_MODE_ALWAYS
		tower.animation_player_2.process_mode = Node.PROCESS_MODE_ALWAYS
		tower.animation_player_3.process_mode = Node.PROCESS_MODE_ALWAYS
		# 已死柱子保留死亡视觉，不再倒放「复活」入场。
		if not _is_tower_alive(tower):
			continue
		tower.animation_player_3.play_backwards(ESCAPE_ANIM)
		if wait_tower == null:
			wait_tower = tower
	if wait_tower != null and is_inside_tree():
		var wait_sec := ESCAPE_ANIM_FALLBACK_SEC
		var wait_player = wait_tower.animation_player_3
		if wait_player != null:
			var wait_anim = wait_player.get_animation(ESCAPE_ANIM)
			if wait_anim != null:
				wait_sec = wait_anim.length
		await get_tree().create_timer(wait_sec + ESCAPE_ANIM_MARGIN_SEC, true, false, true).timeout
	self.visible = false
	for i in tower_group:
		if i != null and is_instance_valid(i):
			i.idle_state.call_deferred()
	PoolManager.erase_pool("erosion_tower")
	queue_free()

# FEVER 内击杀：等死亡动画播完再让回合结算，避免截断掉落表现。
# 等待必须有上限：动画被外部停掉/替换时裸 await 信号会让 FEVER 结算永久挂起。
func boss_intruder_wait_death() -> void:
	if animation_player == null or not is_inside_tree():
		return
	var deadline := Time.get_ticks_msec() + int(DEATH_WAIT_TIMEOUT_SEC * 1000.0)
	while is_instance_valid(animation_player) and animation_player.is_playing() \
			and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05, true, false, true).timeout
	if is_instance_valid(animation_player) and animation_player.is_playing():
		push_warning("erosion_tower_group: 死亡动画等待超时，继续结算")

func boss_enter_anim():
	# 入场演出期间免疫一切伤害（镜像不设）；入场结束后按守卫条件恢复。
	_set_towers_invincible(true)
	for i in tower_group:
		if not i.tower_dead.is_connected(boss_dead):
			i.tower_dead.connect(boss_dead)
		i.animation_player_3.process_mode = Node.PROCESS_MODE_ALWAYS
		i.animation_player_3.play("enter_anim")
	self.visible = true
	# 镜像只播动画，不做相机/暂停演出（否则镜像本地 pause 整棵树）
	if has_meta("network_remote_enemy"):
		return
	# 乱入：不运镜、不暂停，但入场动画结束后仍要开始攻击。
	var no_cinematic := has_meta("boss_intruder")
	if no_cinematic and not has_meta("network_remote_enemy"):
		# 乱入没有 ui_visible 事件：显式显示血条，别依赖场景默认可见。
		var hp_ui := get_node_or_null("BossHP")
		if hp_ui != null and hp_ui.has_method("game_ui_visible"):
			hp_ui.game_ui_visible(true)
	if not no_cinematic:
		GameEvents.emit_camera_move(camera_marker, true)
		GameEvents.emit_ui_visible(false)
		GameEvents.emit_pause_lock(true)
		get_tree().paused = true
	await tower_1.animation_player_3.animation_finished
	for i in tower_group:
		i.animation_player_3.process_mode = Node.PROCESS_MODE_INHERIT
	if not no_cinematic:
		GameEvents.emit_camera_reset()
		GameEvents.emit_ui_visible(true)
		get_tree().paused = false
		GameEvents.emit_pause_lock(false)
	# 入场被退场/死亡打断时：免疫与出招都交给对应流程，别清掉退场免疫、也别死后开火。
	if _dead_started or _intruder_escaping:
		return
	_set_towers_invincible(false)
	attack_state()

func count_now_hp():
	stats.hp = tower_1.stats.hp + tower_2.stats.hp + tower_3.stats.hp

func count_max_hp():
	
	var max_value = tower_1.stats.base_max_hp + tower_2.stats.base_max_hp + tower_3.stats.base_max_hp
	stats.base_max_hp = max_value
	stats.update_body_ability()
	count_now_hp()

func _coin_drops():
	# 远端镜像：不本地生成奖励金币（host 权威同步），保留死亡动画后自释放
	if has_meta("network_remote_enemy"):
		await animation_player.animation_finished
		queue_free()
		return
	var intruder := has_meta("boss_intruder")
	var coin_box = coins.instantiate()
	coin_box.global_position = self.global_position
	coin_box.coin_count = maxi(1, int(stats.Enemy_coin * (0.3 if intruder else 1.0)))
	coin_box.coin_quantity = 30 if intruder else 100
	get_tree().get_first_node_in_group("CoinRoot").add_child(coin_box)
	if not intruder:
		var p_box = pyroxenes.instantiate()
		p_box.global_position = self.global_position
		get_tree().get_first_node_in_group("CoinRoot").add_child(p_box)
	await animation_player.animation_finished
	coin_box.add_coin()
	PoolManager.erase_pool("erosion_tower")
	queue_free()
