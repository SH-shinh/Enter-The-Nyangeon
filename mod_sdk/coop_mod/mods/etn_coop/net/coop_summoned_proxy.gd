extends Node

## CoopSummonedProxy：召唤物同步代理。
##  - 本地拥有者：周期性上报位置/速度/朝向；idle 时请求 despawn。
##  - 远程镜像：按快照插值，禁用物理/AI/碰撞。

const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const SEND_INTERVAL: float = 0.066
const HARD_CORRECT_DISTANCE: float = 128.0
const HARD_CORRECT_DISTANCE_SQUARED: float = HARD_CORRECT_DISTANCE * HARD_CORRECT_DISTANCE
# 快照间隔（与拥有者 SEND_INTERVAL 对应），用于自适应插值延迟
const SNAPSHOT_INTERVAL: float = 0.066
const SnapshotBuffer := preload("res://mods/etn_coop/net/coop_snapshot_buffer.gd")
const DashGhost := preload("res://mods/etn_coop/net/coop_dash_ghost.gd")

var net_id: int = -1
var owner_peer_id: int = 1
var is_local_owner: bool = true
var send_timer: float = 0.0
var target_position: Vector2
var target_velocity: Vector2
var target_rotation: float = 0.0
var target_state: int = -1
var target_facing: int = 1
var despawn_sent: bool = false
var _buffer = SnapshotBuffer.new()
var _last_extrap: bool = false

var summoned: Node = null
var summoned_body: CharacterBody2D = null
var has_velocity_property: bool = false
var has_idle_state: bool = false
var can_apply_rotation: bool = false
var can_get_rotation: bool = false
var has_apply_state: bool = false
var has_get_state: bool = false


func setup(p_net_id: int, p_owner_peer_id: int, p_is_local_owner: bool) -> void:
	summoned = get_parent()
	if summoned == null:
		push_error("[etn_coop] CoopSummonedProxy 必须挂在召唤物节点下")
		return
	summoned_body = summoned as CharacterBody2D
	has_velocity_property = summoned_body == null and summoned.get("velocity") != null
	has_idle_state = summoned.get("is_idle") != null
	can_apply_rotation = summoned.has_method("apply_network_visual_rotation")
	can_get_rotation = summoned.has_method("get_network_visual_rotation")
	has_apply_state = summoned.has_method("apply_network_state")
	has_get_state = summoned.has_method("get_network_state")
	net_id = p_net_id
	owner_peer_id = p_owner_peer_id
	is_local_owner = p_is_local_owner
	target_position = summoned.global_position
	target_rotation = summoned.global_rotation
	_buffer.clear()
	_buffer.push(Time.get_ticks_msec(), target_position, Vector2.ZERO)
	summoned.set_meta("summoned_net_id", net_id)
	summoned.set_meta("owner_peer_id", owner_peer_id)
	summoned.set_meta("is_local_summoned", is_local_owner)
	if is_local_owner and not summoned.tree_exiting.is_connected(_on_summoned_tree_exiting):
		# 无 is_idle 的持久身体（drone/vacuum）或直接 queue_free 的召唤物：以退树作为 despawn 兜底
		summoned.tree_exiting.connect(_on_summoned_tree_exiting)
	if not is_local_owner:
		_disable_remote_simulation()


# 本地拥有者节点退树（换角色/道具移除/场景清）→ 兜底请求 despawn（覆盖无 is_idle 的持久身体）
func _on_summoned_tree_exiting() -> void:
	if despawn_sent or net_id < 0:
		return
	despawn_sent = true
	if multiplayer.multiplayer_peer == null:
		return
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		coop.request_summoned_despawn(net_id)


func apply_state(position: Vector2, velocity: Vector2, rotation: float, state: int = -1, facing: int = 1) -> void:
	target_position = position
	target_velocity = velocity
	target_rotation = rotation
	target_state = state
	target_facing = facing
	_buffer.push(Time.get_ticks_msec(), position, velocity)


func _physics_process(delta: float) -> void:
	var coop = CoopNetScript.instance
	if coop == null or not coop.is_lan_game:
		return
	if multiplayer.multiplayer_peer == null:
		return
	if summoned == null or not is_instance_valid(summoned):
		return
	if is_local_owner:
		if has_idle_state and int(summoned.is_idle) == 1:
			if not despawn_sent:
				despawn_sent = true
				coop.request_summoned_despawn(net_id)
			return
		send_timer -= delta
		if send_timer <= 0.0 and net_id >= 0:
			send_timer = SEND_INTERVAL
			var velocity_value: Vector2 = Vector2.ZERO
			if summoned_body != null:
				velocity_value = summoned_body.velocity
			elif has_velocity_property:
				velocity_value = summoned.velocity
			coop.send_summoned_state(net_id, summoned.global_position, velocity_value, _get_visual_rotation(), _get_state(), _get_facing())
		return
	var old_pos: Vector2 = summoned.global_position
	var tele: bool = _buffer.consume_teleport()
	var render_msec: int = Time.get_ticks_msec() - int(_interp_delay() * 1000.0)
	var vel: Vector2 = target_velocity
	var snapped: bool = false
	if _buffer.sample(render_msec):
		var p: Vector2 = _buffer.sample_pos
		vel = _buffer.sample_vel
		if summoned.global_position.distance_squared_to(p) > HARD_CORRECT_DISTANCE_SQUARED:
			summoned.global_position = p
			_buffer.clear()
			_inc_hard_snap()
			snapped = true
		else:
			summoned.global_position = p
		if _buffer.extrapolating and not _last_extrap:
			_inc_extrap()
		_last_extrap = _buffer.extrapolating
	if (tele or snapped) and old_pos.distance_squared_to(summoned.global_position) > 64.0:
		_spawn_ghost(old_pos)
	if CoopNetScript.instance != null and CoopNetScript.instance.sim_report_enabled:
		CoopNetScript.instance.net_remote_frames += 1
		if _buffer.extrapolating:
			CoopNetScript.instance.net_extrap_frames += 1
	if can_apply_rotation:
		summoned.apply_network_visual_rotation(target_rotation, delta)
	else:
		summoned.global_rotation = lerp_angle(summoned.global_rotation, target_rotation, minf(1.0, delta * 12.0))
	if has_apply_state and target_state >= 0:
		summoned.apply_network_state(target_state, target_facing)
	if summoned_body != null:
		summoned_body.velocity = vel
	elif has_velocity_property:
		summoned.set("velocity", vel)


func _interp_delay() -> float:
	var coop = CoopNetScript.instance
	var rtt: float = 0.0
	var jitter: float = 0.0
	if coop != null and is_instance_valid(coop):
		rtt = coop.net_rtt_ms
		jitter = coop.net_jitter_ms
	return SnapshotBuffer.compute_delay(SNAPSHOT_INTERVAL, rtt, jitter, _buffer.observed_interval_ms())


func _spawn_ghost(old_pos: Vector2) -> void:
	if summoned == null or not is_instance_valid(summoned):
		return
	var p: Node = summoned.get_parent()
	if p == null:
		return
	DashGhost.spawn(get_tree(), p, old_pos, summoned)


func _inc_extrap() -> void:
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		coop.net_extrap_events += 1


func _inc_hard_snap() -> void:
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		coop.net_hard_snaps += 1


func _get_visual_rotation() -> float:
	if can_get_rotation:
		return summoned.get_network_visual_rotation()
	return summoned.global_rotation


func _get_state() -> int:
	if has_get_state:
		return int(summoned.get_network_state())
	return -1


func _get_facing() -> int:
	if summoned.has_method("get_network_facing"):
		return int(summoned.get_network_facing())
	return 1


func _disable_remote_simulation() -> void:
	summoned.set_physics_process(false)
	summoned.set_process_input(false)
	summoned.set_process_unhandled_input(false)
	_disable_damage_nodes(summoned)
	_disable_support_scripts(summoned)
	var state_machine: Node = summoned.get_node_or_null("StateMachine")
	if state_machine != null:
		state_machine.set_physics_process(false)
	if summoned.get("can_move") != null:
		summoned.can_move = false


# 远端镜像上的支援主动（如 kei_as 的 SupportAS）不得参与本机支援逻辑/充能
func _disable_support_scripts(node: Node) -> void:
	if node.has_method("network_disable"):
		node.call("network_disable")
	for child in node.get_children():
		_disable_support_scripts(child)


func _disable_damage_nodes(node: Node) -> void:
	if node is Area2D:
		node.set_deferred("monitoring", false)
		node.set_deferred("monitorable", false)
		node.set_collision_layer(0)
		node.set_collision_mask(0)
		# 停 process：否则本体 hurt_box._physics_process 会继续轮询 _contact_probe.get_overlapping_bodies()
		node.set_physics_process(false)
		node.set_process(false)
	if node is CollisionObject2D:
		node.set_collision_layer(0)
		node.set_collision_mask(0)
	for child in node.get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", true)
		else:
			_disable_damage_nodes(child)
