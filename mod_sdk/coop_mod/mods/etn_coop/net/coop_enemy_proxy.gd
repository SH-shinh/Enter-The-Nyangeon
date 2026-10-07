extends Node

## CoopEnemyProxy：挂在「远程敌人镜像」上，按服务端快照驱动位置/速度/血量。
## 客户端带「预测」：命中时即时下调显示血量，host 快照到达后校正（对齐联机版 NetworkEnemyProxy）。

const HARD_CORRECT_DISTANCE: float = 128.0
const HARD_CORRECT_DISTANCE_SQUARED: float = HARD_CORRECT_DISTANCE * HARD_CORRECT_DISTANCE
const PENDING_TIMEOUT_MSEC: int = 1000
const PENDING_MAX_ENTRIES: int = 48
# 快照间隔（与 CoopNet.ENEMY_SNAPSHOT_INTERVAL 对应），用于自适应插值延迟
const SNAPSHOT_INTERVAL: float = 0.066
const SnapshotBuffer := preload("res://mods/etn_coop/net/coop_snapshot_buffer.gd")
const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const DashGhost := preload("res://mods/etn_coop/net/coop_dash_ghost.gd")

var net_id: int = -1
var target_position: Vector2
var target_velocity: Vector2
var last_snapshot_time: float = 0.0
var _buffer = SnapshotBuffer.new()
var _last_extrap: bool = false

var enemy: Node = null
var enemy_body: CharacterBody2D = null
var enemy_stats = null
var has_velocity_property: bool = false

var auth_hp: int = -1
var pending_damage: int = 0
var display_hp: int = -1
var _pending_at_msec: PackedInt64Array = PackedInt64Array()
var _pending_amount: PackedInt32Array = PackedInt32Array()

# 动画状态（快照驱动，替代镜像本地 AI）
var target_state: int = -1
var _applied_state: int = -1
# 策反态（快照驱动）
var _applied_converted: bool = false
var _applied_gauge: int = -1


func setup(p_net_id: int, server_owned: bool) -> void:
	enemy = get_parent()
	if enemy == null:
		push_error("[etn_coop] CoopEnemyProxy 必须挂在敌人节点上")
		return
	enemy_body = enemy as CharacterBody2D
	enemy_stats = _resolve_stats(enemy)
	has_velocity_property = enemy_body == null and enemy.get("velocity") != null
	net_id = p_net_id
	target_position = enemy.global_position
	_buffer.clear()
	_buffer.push(Time.get_ticks_msec(), target_position, Vector2.ZERO)
	enemy.set_meta("net_id", net_id)
	reset_prediction_state()
	if not server_owned:
		enemy.set_meta("network_remote_enemy", true)
		_disable_network_simulation()
		set_physics_process(true)
	else:
		# host 权威端：代理不参与驱动（避免把敌人钉在初始位置 / 无谓开销）
		set_physics_process(false)


# 镜像停 AI：关根节点物理帧 + StateMachine 物理帧（保留 AnimatedSprite2D 等子节点动画）
func _disable_network_simulation() -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	enemy.set_physics_process(false)
	var sm = enemy.get_node_or_null("StateMachine")
	if sm != null:
		sm.set_physics_process(false)


# 供 CoopNet 在 enemy.active_state()（会重开 AI）之后再次停用
func disable_mirror_ai() -> void:
	_disable_network_simulation()


func _resolve_stats(node: Node):
	var stats = node.get("stats")
	if stats == null:
		return null
	if stats.get("hp") == null or stats.get("max_hp") == null:
		return null
	return stats


func _is_idle_or_gone() -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return true
	var idle = enemy.get("is_idle")
	return idle != null and int(idle) == 1


func reset_prediction_state() -> void:
	auth_hp = -1
	pending_damage = 0
	display_hp = -1
	_pending_at_msec = PackedInt64Array()
	_pending_amount = PackedInt32Array()


# 客机命中预测：立即把镜像显示血量下调，返回预测后显示值
func note_predicted_damage(amount: int) -> int:
	if enemy_stats == null:
		return 0
	_expire_pending()
	if auth_hp < 0:
		auth_hp = maxi(1, int(enemy_stats.get("hp")))
	if amount > 0:
		_pending_at_msec.append(Time.get_ticks_msec())
		_pending_amount.append(amount)
		_recount_pending()
		_trim_pending()
	_write_display(false)
	return auth_hp - pending_damage


func _compute_display() -> int:
	if auth_hp < 0:
		return -1
	if pending_damage <= 0:
		return auth_hp
	return maxi(1, auth_hp - pending_damage)


func _write_display(force_signal: bool) -> int:
	var value: int = _compute_display()
	if value < 0:
		return -1
	display_hp = value
	enemy.set_meta("predicted_hp", value)
	if enemy_stats == null:
		return value
	if enemy_stats.max_hp < value:
		enemy_stats.max_hp = value
	if _is_idle_or_gone():
		return value
	if value > 0 and int(enemy_stats.hp) != value:
		if force_signal and enemy_stats.get("hp_change_cd") != null:
			enemy_stats.set("hp_change_cd", 0)
		enemy_stats.hp = value
	return value


func _reassert_display() -> void:
	if enemy_stats == null or auth_hp < 0 or display_hp <= 0:
		return
	if _is_idle_or_gone():
		return
	if int(enemy_stats.hp) == display_hp:
		return
	_write_display(true)


func _confirm_pending(confirmed: int) -> void:
	var rest: int = confirmed
	while rest > 0 and _pending_amount.size() > 0:
		var head: int = int(_pending_amount[0])
		if head <= rest:
			rest -= head
			_pending_at_msec.remove_at(0)
			_pending_amount.remove_at(0)
		else:
			_pending_amount[0] = head - rest
			rest = 0
	_recount_pending()


func _expire_pending() -> void:
	if pending_damage <= 0 or _pending_at_msec.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var cut: int = 0
	while cut < _pending_at_msec.size() and now - int(_pending_at_msec[cut]) > PENDING_TIMEOUT_MSEC:
		cut += 1
	if cut <= 0:
		return
	_pending_at_msec = _pending_at_msec.slice(cut)
	_pending_amount = _pending_amount.slice(cut)
	_recount_pending()


func _trim_pending() -> void:
	while _pending_amount.size() > PENDING_MAX_ENTRIES:
		_pending_at_msec.remove_at(0)
		_pending_amount.remove_at(0)
	_recount_pending()


func _recount_pending() -> void:
	var total: int = 0
	for amount in _pending_amount:
		total += int(amount)
	pending_damage = maxi(0, total)


func apply_snapshot(position: Vector2, velocity: Vector2, hp: int, state: int = -1, converted: bool = false, gauge: int = 0) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	target_position = position
	target_velocity = velocity
	target_state = state
	var now_ms: int = Time.get_ticks_msec()
	last_snapshot_time = now_ms * 0.001
	_buffer.push(now_ms, position, velocity)
	# 策反态（纯镜像表现；仅在变化时应用）
	if gauge != _applied_gauge or converted != _applied_converted:
		_applied_gauge = gauge
		_applied_converted = converted
		if enemy.has_method("apply_network_conversion"):
			enemy.call("apply_network_conversion", gauge, converted)
	var revived: bool = false
	if enemy.has_meta("predicted_dead") and enemy.get_meta("predicted_dead"):
		if hp > 0:
			_revive_local_mirror()
			revived = true
		else:
			return
	_expire_pending()
	if auth_hp < 0:
		auth_hp = hp
	elif hp > auth_hp:
		auth_hp = hp
	else:
		var confirmed: int = auth_hp - hp
		auth_hp = hp
		if confirmed > 0:
			_confirm_pending(confirmed)
	var value: int = _compute_display()
	if value < 0:
		return
	display_hp = value
	enemy.set_meta("predicted_hp", value)
	if enemy_stats == null:
		return
	if hp > enemy_stats.max_hp:
		enemy_stats.max_hp = hp
	if _is_idle_or_gone():
		return
	if value > 0 and int(enemy_stats.hp) != value:
		if revived and enemy_stats.get("hp_change_cd") != null:
			enemy_stats.set("hp_change_cd", 0)
		enemy_stats.hp = value


# 快照证明镜像仍存活：撤销预测死亡
func _revive_local_mirror() -> void:
	enemy.set_meta("predicted_dead", false)
	if enemy_stats != null:
		if enemy_stats.get("dead_lock") != null:
			enemy_stats.set("dead_lock", false)
		if enemy_stats.get("hurt_hp") != null:
			enemy_stats.set("hurt_hp", 0)
	if enemy.get("is_idle") != null and int(enemy.get("is_idle")) == 1:
		if enemy.has_method("active_state"):
			enemy.call("active_state")
			# active_state 会重开 AI，镜像需再次停用
			_disable_network_simulation()
		else:
			enemy.visible = true
			enemy.set("is_idle", 0)
	_applied_state = -1
	_applied_gauge = -1


func _physics_process(_delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.get("is_idle") != null and int(enemy.is_idle) == 1:
		return
	if pending_damage > 0:
		var before: int = pending_damage
		_expire_pending()
		if pending_damage != before:
			_write_display(false)
	_reassert_display()
	# 缓冲插值：按"过去时间"采样，丢包/抖动下平滑；欠载时按末速度外推（缓入衰减，有上限）
	var old_pos: Vector2 = enemy.global_position
	var tele: bool = _buffer.consume_teleport()
	var render_msec: int = Time.get_ticks_msec() - int(_interp_delay() * 1000.0)
	var vel: Vector2 = target_velocity
	var snapped: bool = false
	if _buffer.sample(render_msec):
		var p: Vector2 = _buffer.sample_pos
		vel = _buffer.sample_vel
		if enemy.global_position.distance_squared_to(p) > HARD_CORRECT_DISTANCE_SQUARED:
			enemy.global_position = p
			_buffer.clear()
			_inc_hard_snap()
			snapped = true
		else:
			enemy.global_position = p
		if _buffer.extrapolating and not _last_extrap:
			_inc_extrap()
		_last_extrap = _buffer.extrapolating
	if (tele or snapped) and old_pos.distance_squared_to(enemy.global_position) > 64.0:
		_spawn_ghost(old_pos)
	if CoopNetScript.instance != null and CoopNetScript.instance.sim_report_enabled:
		CoopNetScript.instance.net_remote_frames += 1
		if _buffer.extrapolating:
			CoopNetScript.instance.net_extrap_frames += 1
	if enemy_body != null:
		enemy_body.velocity = vel
	elif has_velocity_property:
		enemy.set("velocity", vel)
	# 朝向：本体敌人靠自身 move() 按移动方向翻转 graphics.scale.x；镜像物理已关，故按快照速度补翻
	if absf(vel.x) > 1.0:
		var g = enemy.get("graphics")
		if g is Node2D:
			(g as Node2D).scale.x = absf((g as Node2D).scale.x) * signf(vel.x)
	# 动画状态：镜像 AI 已停，由 host 快照的 state 驱动 transition_state（纯表现）
	if target_state >= 0 and target_state != _applied_state:
		if enemy.has_method("transition_state"):
			var from_state: int = _applied_state if _applied_state >= 0 else target_state
			enemy.call("transition_state", from_state, target_state)
		_applied_state = target_state


func _interp_delay() -> float:
	var rtt: float = 0.0
	var jitter: float = 0.0
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		rtt = coop.net_rtt_ms
		jitter = coop.net_jitter_ms
	return SnapshotBuffer.compute_delay(SNAPSHOT_INTERVAL, rtt, jitter, _buffer.observed_interval_ms())


func _spawn_ghost(old_pos: Vector2) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var p: Node = enemy.get_parent()
	if p == null:
		return
	DashGhost.spawn(get_tree(), p, old_pos, enemy)


func _inc_extrap() -> void:
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		coop.net_extrap_events += 1


func _inc_hard_snap() -> void:
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		coop.net_hard_snaps += 1
