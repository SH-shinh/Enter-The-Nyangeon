extends PlayerPS
## Hare 技能（v8）：
## 1) 右键 toggle 智能锁定：瞄准框自动锁敌（槽=框内目标数×比例），齐射追踪弹；
## 2) 锁定期间命中不同目标叠 harec_aim 装备强化层；T1/T2 每 2 次、T3 每次重复命中已标记敌人额外叠层；
## 3) 再按右键退出并释放无人机（4/5s），按层数强化装备伤害/射速；释放结束清层；
## 4) 无人机三态：IDLE 常态索敌 / GUARD 锁定护卫 / RELEASE 释放期输出；锁定耗电、退出回电。

enum Phase { NORMAL, LOCKED, RELEASE }

const HARE_OPTIC := preload("res://ui/hare_optic_overlay.tscn")
const HARE_BATTERY := preload("res://ui/hare_battery.gd")
const HARE_MARK := preload("res://resources/buff/enemy_buff/hare_mark.tres")
const HARE_AIM_BUFF := preload("res://resources/buff/player_buff/hare_aim_buff.tres")
const AIM_BUFF_ID: String = "hare_aim"
const MARK_ID: String = "hare_mark"
const MARK_BONUS: Array[float] = [0.2, 0.3, 0.5, 0.8]

## 槽上限 = 框内目标数 × 该百分比；T3 = 100% 锁全部。
const SLOT_RATIO: Array[float] = [0.4, 0.6, 0.8, 1.0]
const SINGLE_CAP: Array[int] = [3, 3, 3, 4]
## T3 的框半径 = T0 × 2（+100%）。
const LOCK_RADIUS: Array[float] = [120.0, 160.0, 200.0, 240.0]
const LAYER_CAP: Array[int] = [40, 80, 200, 999]
const DRONE_COUNT: Array[int] = [3, 4, 5, 6]
const RELEASE_TIME: Array[float] = [4.0, 4.0, 4.0, 5.0]
const MIN_LOCK_TIME: float = 0.3
const ENERGY_MAX: float = 20.0
const ENERGY_DRAIN: float = 8.0
const ENERGY_REGEN: float = 6.0
const ENERGY_HIT_REGEN: float = 2.0
const AIM_COOLDOWN: float = 1.0

var _local: bool = false
var _phase: int = Phase.NORMAL
var _lock: HareLockManager = null
var _squad: HareDroneSquad = null
var _mirror_squad: HareDroneSquad = null
var _optic: Node = null
var _battery: Node = null
var _energy: float = ENERGY_MAX
var _aim_cd: float = 0.0

var _sync: int = 0
var _lock_elapsed: float = 0.0
var _release_left: float = 0.0
var _release_total: float = 0.0
var _release_extension: float = 0.0
var _enemy_stacks: Dictionary = {}
var _killed: Dictionary = {}
var _crosshair_node: Node = null
var _crosshair_was_visible: bool = true


func _ready() -> void:
	super._ready()
	_local = _is_local_player()
	if not _local:
		call_deferred("_deploy_mirror_drones")
		return
	call_deferred("_deploy")


func _is_local_player() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if bool(player.get_meta("network_remote_player", false)):
		return false
	return player.is_in_group("Player")


func _tier() -> int:
	return clampi(now_t, 0, 3)


func _deploy() -> void:
	if not _local or player == null or not is_instance_valid(player):
		return
	if player.get_node_or_null("HareLockManager") != null:
		return
	_lock = HareLockManager.new()
	_lock.name = "HareLockManager"
	_lock.player = player
	_lock.z_index = 60
	player.add_child(_lock)

	_squad = HareDroneSquad.new()
	_squad.name = "HareDroneSquad"
	_squad.player = player
	# 世界层化：编队全局变换不继承玩家位移，IDLE 跟随才能产生 Chihiro 式拖尾。
	_squad.top_level = true
	player.add_child(_squad)
	_squad.global_position = Vector2.ZERO

	_optic = HARE_OPTIC.instantiate()
	player.add_child(_optic)

	_battery = HARE_BATTERY.new()
	_battery.player = player
	player.add_child(_battery)
	_battery.update_energy(_energy, ENERGY_MAX)

	if not GameEvents.player_bullet_hit_enemy.is_connected(_on_bullet_hit):
		GameEvents.player_bullet_hit_enemy.connect(_on_bullet_hit)
	if not GameEvents.round_end.is_connected(_on_round_end):
		GameEvents.round_end.connect(_on_round_end)
	_apply_tier()


# ---------------- 镜像玩家：纯视觉无人机（不开火/不结算） ----------------

func _host_layer() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var layer := tree.get_first_node_in_group("EquipLayer")
	if layer != null:
		return layer
	layer = tree.get_first_node_in_group("PlayerRoot")
	if layer != null:
		return layer
	if player != null and is_instance_valid(player):
		return player.get_parent()
	return null


func _deploy_mirror_drones() -> void:
	if _local or player == null or not is_instance_valid(player):
		return
	if _mirror_squad != null and is_instance_valid(_mirror_squad):
		return
	var host := _host_layer()
	if host == null:
		return
	_mirror_squad = HareDroneSquad.new()
	_mirror_squad.name = "HareMirrorSquad"
	_mirror_squad.player = player
	_mirror_squad.mirror_only = true
	_mirror_squad.top_level = true
	host.add_child(_mirror_squad)
	_mirror_squad.global_position = Vector2.ZERO
	_sync_mirror_drones()


func _sync_mirror_drones() -> void:
	if _local or _mirror_squad == null or not is_instance_valid(_mirror_squad):
		return
	_mirror_squad.set_count(DRONE_COUNT[_tier()])


# 联机：拥有者 PS 升级 → 镜像端按 tier 重建视觉无人机
func network_set_tier(t: int) -> void:
	if _local:
		return
	now_t = clampi(t, 0, 3)
	_sync_mirror_drones()


# 由 player.apply_network_character_event 转发（无需改 coop mod）
func apply_network_character_event(event_name: StringName, event_data: Dictionary) -> void:
	if event_name == "hare_ps_tier":
		network_set_tier(int(event_data.get("tier", 0)))


func _process(delta: float) -> void:
	if not _local:
		return
	if player == null or not is_instance_valid(player):
		return
	if player.player_stop or (player.stats != null and int(player.stats.hp) <= 0):
		if _phase != Phase.NORMAL:
			_reset_state()
		return
	if _phase == Phase.LOCKED:
		_lock_elapsed += delta
		_energy = maxf(0.0, _energy - ENERGY_DRAIN * delta)
		if _energy <= 0.0:
			_exit_locked()
	elif _phase == Phase.RELEASE:
		_release_left -= delta
		if _release_left <= 0.0:
			_end_release()
	if _phase != Phase.LOCKED:
		_energy = minf(ENERGY_MAX, _energy + ENERGY_REGEN * delta)
	_aim_cd = maxf(0.0, _aim_cd - delta)
	if _battery != null:
		_battery.update_energy(_energy, ENERGY_MAX)


func _unhandled_input(event: InputEvent) -> void:
	if not _local or player == null or player.player_stop:
		return
	if not event.is_action_pressed("hare_aim"):
		return
	if _aim_cd > 0.0:
		get_viewport().set_input_as_handled()
		return
	if _phase == Phase.NORMAL or _phase == Phase.RELEASE:
		_enter_locked()
		_aim_cd = AIM_COOLDOWN
	elif _phase == Phase.LOCKED and _lock_elapsed >= MIN_LOCK_TIME:
		_exit_locked()
		_aim_cd = AIM_COOLDOWN
	get_viewport().set_input_as_handled()


# ---------------- 形态切换 ----------------

func _enter_locked() -> void:
	_phase = Phase.LOCKED
	_sync = 0
	_lock_elapsed = 0.0
	_enemy_stacks.clear()
	_killed.clear()
	_release_extension = 0.0
	# 从 RELEASE 直接重新进入：中断释放、无人机回 GUARD。
	_release_left = 0.0
	_release_total = 0.0
	if _lock != null:
		_lock.set_active(true)
	if _squad != null:
		_squad.set_release_level(0)
		_squad.set_mode(HareDrone.Mode.GUARD)
	_clear_aim_buff()
	SoundManager.play_sfx("HareLockIn")
	_hide_crosshair()
	if _optic != null:
		_optic.set_active(true)


func _exit_locked() -> void:
	_phase = Phase.RELEASE
	if _lock != null:
		_lock.set_active(false)
	if _squad != null:
		_squad.set_release_level(_sync)
		_squad.set_mode(HareDrone.Mode.RELEASE)
	_release_total = RELEASE_TIME[_tier()]
	_release_left = _release_total
	_release_extension = 0.0
	_killed.clear()
	# buff 持续时间与无人机释放同步：从退出锁定开始计时。
	_refresh_aim_buff(_release_total)
	SoundManager.play_sfx("HareLockOut")
	_show_crosshair()
	if _optic != null:
		_optic.set_active(false)


func _end_release() -> void:
	_phase = Phase.NORMAL
	_release_left = 0.0
	_sync = 0
	_enemy_stacks.clear()
	_killed.clear()
	if _squad != null:
		_squad.set_mode(HareDrone.Mode.IDLE)
		_squad.set_release_level(0)
	_clear_aim_buff()


func _reset_state() -> void:
	_phase = Phase.NORMAL
	_sync = 0
	_lock_elapsed = 0.0
	_release_left = 0.0
	_enemy_stacks.clear()
	_killed.clear()
	if _lock != null:
		_lock.set_active(false)
	if _squad != null:
		_squad.set_mode(HareDrone.Mode.IDLE)
		_squad.set_release_level(0)
	_clear_aim_buff()
	_show_crosshair()
	if _optic != null:
		_optic.call("force_off")
	_energy = ENERGY_MAX
	_aim_cd = 0.0
	if _battery != null:
		_battery.update_energy(_energy, ENERGY_MAX)


func _hide_crosshair() -> void:
	if _crosshair_node != null and is_instance_valid(_crosshair_node):
		return
	_crosshair_node = get_tree().get_first_node_in_group("crosshair")
	if _crosshair_node == null:
		_crosshair_node = get_tree().root.find_child("Crosshair", true, false)
	if _crosshair_node == null:
		return
	_crosshair_was_visible = bool(_crosshair_node.get("visible"))
	_crosshair_node.set("visible", false)


func _show_crosshair() -> void:
	if _crosshair_node == null or not is_instance_valid(_crosshair_node):
		_crosshair_node = null
		return
	_crosshair_node.set("visible", _crosshair_was_visible)
	_crosshair_node = null


func _on_round_end() -> void:
	_reset_state()


func _exit_tree() -> void:
	if _mirror_squad != null and is_instance_valid(_mirror_squad):
		_mirror_squad.queue_free()
	_mirror_squad = null


# 节点释放时兜底：锁定中直接归位，确保目镜不会残留。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_phase = Phase.NORMAL
		if _optic != null and is_instance_valid(_optic):
			_optic.call("force_off")


# ---------------- 锁定层 ----------------

func is_locked() -> bool:
	return _phase == Phase.LOCKED


func get_locked_entries() -> Array:
	if _lock == null:
		return []
	return _lock.get_locked_entries()


func _sync_cap() -> int:
	return LAYER_CAP[_tier()]


func _clear_aim_buff() -> void:
	var mgr = player.get("player_buff_manager") if player != null else null
	if mgr != null:
		mgr.remove_buff(HARE_AIM_BUFF)


# buff 持续时间与无人机释放同步：重建层数并统一 duration。
func _refresh_aim_buff(duration: float) -> void:
	var mgr = player.get("player_buff_manager") if player != null else null
	if mgr == null:
		return
	mgr.remove_buff(HARE_AIM_BUFF)
	for i in _sync:
		mgr.apply_buff(HARE_AIM_BUFF, [_sync_cap(), 1, duration], AIM_BUFF_ID)


func _extend_aim_buff(seconds: float) -> void:
	var mgr = player.get("player_buff_manager") if player != null else null
	if mgr == null:
		return
	var entry = mgr.current_buff.get(AIM_BUFF_ID)
	if entry != null:
		entry["erase_time"] = float(entry.get("erase_time", 0.0)) + seconds * 10.0
		mgr.call("_update_card", entry)


func add_energy(amount: float) -> void:
	_energy = clampf(_energy + amount, 0.0, ENERGY_MAX)
	if _battery != null:
		_battery.update_energy(_energy, ENERGY_MAX)


func mark_bonus() -> float:
	return MARK_BONUS[_tier()]


func _apply_mark(victim: Node) -> void:
	var mgr = victim.get("enemy_buff_manager")
	if mgr == null:
		return
	var bonus: float = mark_bonus()
	if mgr.current_buff.has(MARK_ID):
		var entry = mgr.current_buff[MARK_ID]
		if is_equal_approx(float(entry.get("value", -1.0)), bonus):
			return
		mgr.remove_buff(HARE_MARK)
	mgr.apply_buff(HARE_MARK, [1, bonus, 10.0], "hare_locked_shot")


func _on_bullet_hit(bullet: Node, victim: Node) -> void:
	if bullet == null or not is_instance_valid(bullet):
		return
	if not bool(bullet.get_meta("hare_locked_shot", false)):
		return
	if victim == null or not is_instance_valid(victim):
		return
	# 锁定弹命中过的敌人打上智能标记（释放期飞出的锁定弹同样生效）。
	_apply_mark(victim)
	if _phase == Phase.RELEASE:
		_try_extend_release(victim)
		return
	if _phase != Phase.LOCKED:
		return
	# 不同目标首次命中 +1 层；已命中过的目标按 T1/T2（每 2 次）、T3（每次）重复叠层。
	var id: int = victim.get_instance_id()
	if not _enemy_stacks.has(id):
		_enemy_stacks[id] = 0
		_add_aim_stack()
		return
	var need: int = _repeat_hits_needed()
	if need <= 0:
		return
	var hits: int = int(_enemy_stacks[id]) + 1
	if hits >= need:
		_enemy_stacks[id] = 0
		_add_aim_stack()
	else:
		_enemy_stacks[id] = hits


# T1/T2 每 2 次重复命中 +1 层；T3 每次重复命中 +1；T0 不启用。
func _repeat_hits_needed() -> int:
	match _tier():
		1, 2:
			return 2
		3:
			return 1
		_:
			return 0


func _add_aim_stack() -> void:
	_sync = mini(_sync + 1, _sync_cap())
	if player == null:
		return
	var mgr = player.get("player_buff_manager")
	if mgr != null:
		mgr.apply_buff(HARE_AIM_BUFF, [_sync_cap(), 1, 9999.0], AIM_BUFF_ID)


# T3：释放期击杀延长 0.5s（累计上限 +2s）。
func _try_extend_release(victim: Node) -> void:
	if _tier() < 3:
		return
	if victim == null or not is_instance_valid(victim):
		return
	var st = victim.get("stats")
	if st == null or int(st.get("hp")) > 0:
		return
	var id: int = victim.get_instance_id()
	if _killed.has(id):
		return
	_killed[id] = true
	if _release_extension >= 2.0:
		return
	_release_extension += 0.5
	_release_left += 0.5
	_release_total += 0.5
	_extend_aim_buff(0.5)


# ---------------- 升级 ----------------

func ps_upgrade(t_num: int) -> void:
	super.ps_upgrade(t_num)
	if not _local:
		return
	now_t = clampi(t_num, 0, 3)
	_apply_tier()
	# 镜像玩家靠这条事件同步 PS 等级（决定视觉无人机台数）。
	if player != null and is_instance_valid(player):
		player.broadcast_character_event("hare_ps_tier", {"tier": t_num})


func _apply_tier() -> void:
	var t := _tier()
	if _lock != null:
		_lock.set_params(SINGLE_CAP[t], LOCK_RADIUS[t])
		_lock.set_slot_ratio(SLOT_RATIO[t])
	if _squad != null:
		_squad.set_count(DRONE_COUNT[t])
	_sync = mini(_sync, _sync_cap())
