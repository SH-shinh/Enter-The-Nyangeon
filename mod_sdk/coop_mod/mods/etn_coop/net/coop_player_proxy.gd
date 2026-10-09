extends Node

## CoopPlayerProxy：挂在「远程玩家」节点上，驱动其表现并禁用本地控制/信号。
## 本地玩家不挂本 proxy（其状态由 CoopNet 直接发送）。

const HARD_CORRECT_DISTANCE: float = 96.0
const HARD_CORRECT_DISTANCE_SQUARED: float = HARD_CORRECT_DISTANCE * HARD_CORRECT_DISTANCE
# 玩家状态快照间隔（与 CoopNet.STATE_SEND_INTERVAL 对应），用于自适应插值延迟
const SNAPSHOT_INTERVAL: float = 0.05
const SnapshotBuffer := preload("res://mods/etn_coop/net/coop_snapshot_buffer.gd")
const CoopNetScript := preload("res://mods/etn_coop/net/coop_net.gd")
const DashGhost := preload("res://mods/etn_coop/net/coop_dash_ghost.gd")
const DEFAULT_SPRITE_Y: float = -17.0
const DEFAULT_HALO_OFFSET: float = 17.0
const DEFAULT_GUN_ROOT: float = 9.0
const DEFAULT_HAT_POSITION: float = 13.0

var peer_id: int = 1
var is_local_player: bool = false

var target_position: Vector2
var target_velocity: Vector2
var target_look_position: Vector2
var target_sprite_y: float = DEFAULT_SPRITE_Y
var target_state: int = 0
var target_character_state: int = 0
var applied_character_state: int = -1
var target_heading: Vector2 = Vector2.ZERO
var current_visual_state: int = -1
var can_apply_character_state: bool = false
var can_apply_heading: bool = false

var player: Node = null
var player_body: CharacterBody2D = null
var player_stats = null
var player_sprite: AnimatedSprite2D = null
var player_gun: Node2D = null
var player_kick: Node2D = null
var second_gun: Node2D = null
var halo_root: Node2D = null
var halo: Node2D = null
var graphics: Node2D = null
var graphics_gun: Node2D = null
var graphics_halo: Node2D = null
var graphics_gun_hat: Node2D = null
var smoke_node: Node = null
var state_machine: Node = null
var camera_2d: Camera2D = null
var game_ui: CanvasLayer = null
var player_canvas_layer: CanvasLayer = null
var hurt_box: Node = null
var pick_box: Node = null

var halo_root_offset: float = DEFAULT_HALO_OFFSET
var gun_root_offset: float = DEFAULT_GUN_ROOT
var hat_position: float = DEFAULT_HAT_POSITION
var is_mortar: bool = false
var has_long_hair: bool = false
var _buffer = SnapshotBuffer.new()
var _last_extrap: bool = false


func setup(p_peer_id: int, p_is_local: bool) -> void:
	player = get_parent()
	if player == null:
		push_error("[etn_coop] CoopPlayerProxy 必须挂在玩家节点下")
		return
	_cache_references()
	peer_id = p_peer_id
	is_local_player = p_is_local
	target_position = player.global_position
	target_look_position = player.global_position + Vector2.RIGHT
	_buffer.clear()
	_buffer.push(Time.get_ticks_msec(), target_position, Vector2.ZERO)
	player.set_meta("peer_id", peer_id)
	player.set_meta("is_local_player", is_local_player)
	if player_stats != null:
		player.set_meta("net_hp", player_stats.hp)
	if is_local_player:
		return
	player.set_meta("network_remote_player", true)
	_disable_local_nodes()
	_disconnect_remote_global_signals()
	_disable_input_recursive(player)
	if player.get("can_control") != null:
		player.can_control = false
	if player.get("can_move") != null:
		player.can_move = false
	if player.get("player_stop") != null:
		player.player_stop = true
	if player_gun != null and player_gun.get("is_shoot") != null:
		player_gun.is_shoot = false
	# 镜像枪惰性：本体 player_gun.gd 用 get_first_node_in_group("Player")（本机）并 _physics_process 自动连发，
	# 不停会让镜像枪朝本机玩家开火
	if player_gun != null:
		player_gun.set_physics_process(false)
		player_gun.set_process(false)
	# 第二把枪（如 tsurugi）：同样会连发，一并停用并锁 is_shoot=false，防本地生成本地子弹；
	# 其开火表现由 mod 的 _remote_player_gun_shoot 直接调 _shootAnim 回放，瞄准由 _apply_weapon_look 负责。
	if second_gun != null:
		if second_gun.get("is_shoot") != null:
			second_gun.is_shoot = false
		second_gun.set_physics_process(false)
		second_gun.set_process(false)
	if state_machine != null:
		state_machine.set_physics_process(false)
	_disable_areas(player)
	_make_invulnerable()


func apply_state(
	position: Vector2,
	velocity: Vector2,
	look_position: Vector2,
	hp: int,
	ammo: int,
	sprite_y: float = DEFAULT_SPRITE_Y,
	state: int = 0,
	character_state: int = 0,
	heading: Vector2 = Vector2.ZERO,
	max_hp: int = -1,
	t_hp: int = 0,
	max_t_hp: int = -1
) -> void:
	target_position = position
	target_velocity = velocity
	target_look_position = look_position
	target_sprite_y = sprite_y
	target_state = state
	target_character_state = character_state
	target_heading = heading
	_buffer.push(Time.get_ticks_msec(), position, velocity)
	if is_local_player or player_stats == null:
		return
	player.set_meta("net_hp", hp)
	# 先同步 max_hp（升级会提升），否则用镜像基础 max_hp 钳制会显示错误血条
	if max_hp > 0 and int(player_stats.max_hp) != max_hp:
		player_stats.max_hp = max_hp
	# 临时生命上限（默认 max_hp/2，可被升级改变）；先设上限再设值（setter 依赖上限钳制）
	if max_t_hp > 0 and int(player_stats.max_t_hp) != max_t_hp:
		player_stats.max_t_hp = max_t_hp
	var resolved_t_hp: int = clampi(t_hp, 0, maxi(0, int(player_stats.max_t_hp)))
	player.set_meta("net_t_hp", resolved_t_hp)
	player_stats.t_hp = resolved_t_hp
	# 远程玩家不本地判死：clamp 到至少 1，避免触发玩家死亡/游戏结束链路
	player_stats.hp = clampi(hp, 1, maxi(1, player_stats.max_hp))
	if player_stats.get("ammo") != null:
		player_stats.ammo = ammo


func _physics_process(delta: float) -> void:
	if is_local_player:
		return
	if multiplayer.multiplayer_peer == null:
		return
	if player == null or not is_instance_valid(player):
		return
	var old_pos: Vector2 = player.global_position
	var tele: bool = _buffer.consume_teleport()
	var render_msec: int = Time.get_ticks_msec() - int(_interp_delay() * 1000.0)
	var vel: Vector2 = target_velocity
	var snapped: bool = false
	if _buffer.sample(render_msec):
		var p: Vector2 = _buffer.sample_pos
		vel = _buffer.sample_vel
		if player.global_position.distance_squared_to(p) > HARD_CORRECT_DISTANCE_SQUARED:
			player.global_position = p
			_buffer.clear()
			_inc_hard_snap()
			snapped = true
		else:
			player.global_position = p
		if _buffer.extrapolating and not _last_extrap:
			_inc_extrap()
		_last_extrap = _buffer.extrapolating
	if (tele or snapped) and old_pos.distance_squared_to(player.global_position) > 64.0:
		_spawn_ghost(old_pos)
	if CoopNetScript.instance != null and CoopNetScript.instance.sim_report_enabled:
		CoopNetScript.instance.net_remote_frames += 1
		if _buffer.extrapolating:
			CoopNetScript.instance.net_extrap_frames += 1
	if player_body != null:
		player_body.velocity = vel
	if player.has_method("set_player_lookat"):
		player.set_player_lookat(target_look_position)
	_apply_weapon_look()
	_apply_visual_state(delta)


func _apply_weapon_look() -> void:
	if target_look_position.is_equal_approx(player.global_position):
		return
	if player_gun != null:
		if is_mortar:
			_apply_mortar_look(player_gun)
		else:
			player_gun.look_at(target_look_position)
	if player_kick != null and player_kick.get("can_r") != false:
		player_kick.look_at(target_look_position)
	if second_gun != null:
		second_gun.look_at(target_look_position)


func _apply_mortar_look(gun_node: Node2D) -> void:
	var r: float = player.get_angle_to(target_look_position)
	if r <= 0 and r > - PI / 2:
		gun_node.rotation = r * 0.2 - PI * 0.4
	elif r <= - PI / 2:
		gun_node.rotation = - r * 0.2 - PI * 0.6
	elif r > 0 and r <= PI / 2:
		gun_node.rotation = - r * 0.2 - PI * 0.4
	elif r > PI / 2:
		gun_node.rotation = r * 0.2 - PI * 0.6


func _apply_visual_state(delta: float) -> void:
	var visual_state_changed: bool = current_visual_state != target_state
	if player_sprite != null:
		player_sprite.position.y = lerpf(player_sprite.position.y, target_sprite_y, 0.45)
		_play_remote_animation(player_sprite, target_state)
		# 身体瞄准旋转（本体 player.gd:233/256-259 会做，镜像 player_stop=true 不会跑，补上）
		if target_look_position != Vector2.ZERO and not target_look_position.is_equal_approx(player.global_position):
			player_sprite.look_at(target_look_position)
			if player_sprite.rotation_degrees > 5:
				player_sprite.rotation_degrees = 5
			elif player_sprite.rotation_degrees < -10:
				player_sprite.rotation_degrees = -10
	if player_gun != null:
		player_gun.position.y = target_sprite_y + gun_root_offset
	if halo_root != null:
		halo_root.position.y = target_sprite_y - halo_root_offset
	if halo != null and halo_root != null and halo.position.distance_to(halo_root.position) > 0:
		halo.position = halo.position.lerp(halo_root.position, minf(1.0, 5.0 * delta))
	if has_long_hair:
		if graphics_gun_hat != null:
			graphics_gun_hat.position.y = target_sprite_y - hat_position
		if graphics != null:
			if graphics_gun != null:
				graphics_gun.scale.x = graphics.scale.x
			if graphics_halo != null:
				graphics_halo.scale.x = graphics.scale.x
	if visual_state_changed:
		if smoke_node != null and smoke_node.get("emitting") != null:
			smoke_node.emitting = target_state == 1 or target_state == 2
		player.z_index = 3 if target_state >= 2 else 0
	current_visual_state = target_state
	if can_apply_character_state and applied_character_state != target_character_state:
		applied_character_state = target_character_state
		player.call("apply_network_character_state", target_character_state)
	if can_apply_heading and target_heading != Vector2.ZERO:
		player.call("apply_network_heading_direction", target_heading)


func _play_remote_animation(sprite: AnimatedSprite2D, state: int) -> void:
	if sprite == null or current_visual_state == state:
		return
	if state == 0:
		sprite.play("idle")
	elif state == 1:
		sprite.play("run")
	else:
		sprite.play("jump")


# ---------------- 禁用本地控制 / 信号 ----------------

func _cache_references() -> void:
	player_body = player as CharacterBody2D
	player_stats = player.get("stats")
	player_sprite = player.get("sprite_2d") as AnimatedSprite2D
	if player_sprite == null:
		player_sprite = player.find_child("AnimatedSprite2D", true, false) as AnimatedSprite2D
	player_gun = player.get("gun") as Node2D
	player_kick = player.get("kick") as Node2D
	if player_kick != null:
		second_gun = player_kick.get("second_gun") as Node2D
	halo_root = player.get("halo_root") as Node2D
	halo = player.get("halo") as Node2D
	graphics = player.get("graphics") as Node2D
	smoke_node = player.get("smoke")
	state_machine = player.get_node_or_null("StateMachine")
	camera_2d = player.get_node_or_null("Camera2D") as Camera2D
	game_ui = player.get_node_or_null("GameUI") as CanvasLayer
	player_canvas_layer = player.get_node_or_null("CanvasLayer") as CanvasLayer
	hurt_box = player.get("hurt_box")
	pick_box = player.get_node_or_null("PickBox")
	graphics_gun = player.get_node_or_null("GraphicsGun") as Node2D
	graphics_halo = player.get_node_or_null("GraphicsHalo") as Node2D
	if graphics_gun != null:
		graphics_gun_hat = graphics_gun.get_node_or_null("Hat") as Node2D
	if player.get("halo_root_position") != null:
		halo_root_offset = float(player.get("halo_root_position"))
	if player.get("gun_root") != null:
		gun_root_offset = float(player.get("gun_root"))
	if player.get("hat_position") != null:
		hat_position = float(player.get("hat_position"))
	if player.get("mortar") != null:
		is_mortar = bool(player.get("mortar"))
	if player.get("long_hair") != null:
		has_long_hair = bool(player.get("long_hair"))
	can_apply_character_state = player.has_method("apply_network_character_state")
	can_apply_heading = player.has_method("apply_network_heading_direction")


func _disable_local_nodes() -> void:
	if camera_2d != null:
		camera_2d.enabled = false
	if game_ui != null:
		game_ui.visible = false
	if player_canvas_layer != null:
		player_canvas_layer.visible = false


func _disconnect_remote_global_signals() -> void:
	_disconnect_source_signals(GameEvents)
	_disconnect_source_signals(PlayerData)


func _disconnect_source_signals(source: Object) -> void:
	if source == null:
		return
	for signal_info in source.get_signal_list():
		var signal_name: StringName = signal_info["name"]
		for connection in source.get_signal_connection_list(signal_name):
			var callable: Callable = connection["callable"]
			var target: Object = callable.get_object()
			if target is Node and _is_node_in_remote_player(target):
				if source.is_connected(signal_name, callable):
					source.disconnect(signal_name, callable)


func _is_node_in_remote_player(node: Node) -> bool:
	return node == player or player.is_ancestor_of(node)


func _disable_input_recursive(node: Node) -> void:
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	for child in node.get_children():
		_disable_input_recursive(child)


func _disable_areas(node: Node) -> void:
	# Area2D（受击/攻击判定）全部禁用；CharacterBody2D 本体碰撞保留（对齐联机版，避免穿模）
	if node is Area2D:
		node.set_deferred("monitoring", false)
		node.set_deferred("monitorable", false)
		node.set_collision_layer(0)
		node.set_collision_mask(0)
		# 必须同时停 process：本体 hurt_box._physics_process 会轮询 _contact_probe.get_overlapping_bodies()，
		# monitoring 关掉后仍轮询会刷 "Can't find overlapping bodies when monitoring is off."
		node.set_physics_process(false)
		node.set_process(false)
		for child in node.get_children():
			if child is CollisionShape2D:
				child.set_deferred("disabled", true)
		return
	if node is CollisionObject2D and not (node is CharacterBody2D):
		node.set_collision_layer(0)
		node.set_collision_mask(0)
	for child in node.get_children():
		_disable_areas(child)


func _make_invulnerable() -> void:
	if hurt_box == null or not hurt_box.has_method("set_invulnerable"):
		return
	hurt_box.call("set_invulnerable", true)


func _interp_delay() -> float:
	var rtt: float = 0.0
	var jitter: float = 0.0
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		rtt = coop.net_rtt_ms
		jitter = coop.net_jitter_ms
	return SnapshotBuffer.compute_delay(SNAPSHOT_INTERVAL, rtt, jitter, _buffer.observed_interval_ms())


func _spawn_ghost(old_pos: Vector2) -> void:
	if player == null or not is_instance_valid(player):
		return
	var p: Node = player.get_parent()
	if p == null:
		return
	DashGhost.spawn(get_tree(), p, old_pos, player, player_sprite)


func _inc_extrap() -> void:
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		coop.net_extrap_events += 1


func _inc_hard_snap() -> void:
	var coop = CoopNetScript.instance
	if coop != null and is_instance_valid(coop):
		coop.net_hard_snaps += 1
