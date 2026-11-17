extends PlayerPS

## OTOSE KOTAMA 被动：
## 停止射击 2s → 原地留下全息影像 + 自身隐身；
## 开火破隐，破隐这一发必暴击；若命中时在目标背后，额外 ×2（+100%，独立乘区）；
## 全息在破隐后固定维持 0.5s，然后消失。

const HOLOGRAM_SCENE := preload("res://scenes/player/kotama/kotama_hologram.tscn")
const BREAK_MUZZLE_SCENE := preload("res://scenes/effects/kotama_break_muzzle.tscn")
const STEALTH_BUFF := preload("res://resources/buff/player_buff/stealth.tres")
const STEALTH_SOURCE := "kotama_ps"
const BACKSTAB_BONUS: Array[float] = [0.0, 0.5, 1.0, 1.5]
const IDLE_SECONDS: float = 2.0
const LINGER_SECONDS: float = 0.5
const STEALTH_DURATION: float = 5.0
const THREAT_SILENCE_SECONDS: float = 0.5
const BREAK_BACKSTAB_MULT_BY_TIER: Array[float] = [2.0, 2.0, 3.0, 3.0]
const BREAK_SHOT_META := &"kotama_break_shot"
const BREAK_REFUND_META := &"refund_penetrate_on_kill"
const BREAK_VOLLEY_MS: int = 60

const KOTAMA_MARK := preload("res://resources/buff/enemy_buff/kotama_mark.tres")
const MARK_VULN: Array[float] = [0.0, 0.0, 0.8, 2.0]
const MARK_SECONDS: float = 5.0
const HOLO_MARK_RADIUS: float = 180.0
const HOLO_MARK_INTERVAL: float = 1.0
const ECHO_MARK_RADIUS: float = 180.0
const ECHO_LINGER_SECONDS: float = 2.0
const KILL_CD_REDUCTION: float = 0.2
const MAX_CD_REDUCTION: float = 0.8
const KOTAMA_NET_SOURCE := "kotama_net"
const HOLO_NET_SAFETY_SECONDS: float = 8.0

enum Phase { IDLE, STEALTH, BROKEN }

var _local: bool = false
var _phase: int = Phase.IDLE
var _shot_idle: float = 0.0
var _hologram: Node = null
var _backstab_bonus: float = BACKSTAB_BONUS[0]
var _backstab_passive: Node = null
var _break_volley_until_msec: int = 0
## round_end/round_upgrade 到 round_start 之间冻结被动，避免回合末过渡累计停火时间。
var _passive_locked: bool = false
var _break_kills: int = 0
var _next_idle_seconds: float = IDLE_SECONDS
var _holo_mark_accum: float = 0.0
var _echo_holograms: Array[Node] = []
var _echo_used_in_break: bool = false
var _next_holo_net_id: int = 1
var _remote_holos: Dictionary = {}

func _ready() -> void:
	super._ready()
	_local = _is_local_player()
	if not _local:
		_connect_remote_cleanup()
		return
	_phase = Phase.IDLE
	_shot_idle = 0.0
	_backstab_bonus = BACKSTAB_BONUS[_tier()]
	call_deferred("_setup_backstab_passive")
	GameEvents.player_shot_position.connect(_on_player_shot)
	GameEvents.player_bullet_hit_enemy.connect(_on_bullet_hit_enemy)
	GameEvents.enemy_damage_calculating.connect(_on_enemy_damage_calculating)
	GameEvents.round_end.connect(_on_round_end)
	GameEvents.round_upgrade.connect(_on_round_upgrade)
	GameEvents.round_start.connect(_on_round_start)
	GameEvents.test_room_reset.connect(_on_test_reset)
	GameEvents.game_over.connect(_on_game_over)

func _is_local_player() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if bool(player.get_meta("network_remote_player", false)):
		return false
	return player.is_in_group("Player")

func _tier() -> int:
	return clampi(now_t, 0, 3)

func _setup_backstab_passive() -> void:
	if not _local or player == null or not is_instance_valid(player):
		return
	_backstab_passive = BackstabPassive.attach(player, {"bonus": _backstab_bonus})

func ps_upgrade(t_num: int) -> void:
	super.ps_upgrade(t_num)
	if not _local:
		return
	_backstab_bonus = BACKSTAB_BONUS[_tier()]
	if _backstab_passive != null and is_instance_valid(_backstab_passive):
		_backstab_passive.configure({"bonus": _backstab_bonus})

func _process(delta: float) -> void:
	if not _local or player == null or not is_instance_valid(player):
		return
	if bool(player.get("is_downed")) or player.stats == null or int(player.stats.hp) <= 0:
		_clear_all()
		return
	if _passive_locked:
		# 回合末/升级期间不累计停火时间；异常残留的隐身/全息一并清掉。
		if _phase != Phase.IDLE:
			_clear_all()
		return
	if _phase == Phase.STEALTH and not player.is_stealthed():
		# Buff 被外部移除/过期：不要保持“假隐身”；结束后给 0.5s 0 仇恨窗口。
		_clear_all(true)
		return
	if _phase == Phase.STEALTH and not _hologram_is_valid():
		# 全息被外部清掉（切场景/异常）：不要保持“假隐身”，同样保留 0 仇恨窗口。
		_set_stealth_state(false, true)
		_phase = Phase.IDLE
		_shot_idle = 0.0
		return
	_tick_hologram_mark(delta)
	if _phase != Phase.IDLE:
		return
	_shot_idle += delta
	if _shot_idle >= _next_idle_seconds:
		_spawn_hologram()

func _spawn_hologram() -> void:
	if player == null or not is_instance_valid(player):
		return
	var layer := _world_layer()
	if layer == null:
		return
	var holo := HOLOGRAM_SCENE.instantiate()
	layer.add_child(holo)
	holo.global_position = player.global_position
	holo.call("setup", _player_flip())
	_holo_tree_exit_connect(holo)
	_hologram = holo
	_phase = Phase.STEALTH
	_shot_idle = 0.0
	_reset_break_state()
	_set_stealth_state(true)
	if not player.is_stealthed():
		# Buff 没挂上（manager 缺失/audience 不匹配等）：不要留下假隐身。
		_clear_all()
		return
	var net_id := _alloc_holo_net_id()
	_connect_holo_net(holo, net_id)
	_broadcast_kotama_event(&"kotama_holo_spawn", {
		"id": net_id,
		"pos": holo.global_position,
		"facing": _player_flip(),
		"weight": 2.0,
	})
	_pulse_hologram_mark()

func _tick_hologram_mark(delta: float) -> void:
	if _tier() < 2 or not _hologram_is_valid():
		_holo_mark_accum = 0.0
		return
	_holo_mark_accum += delta
	if _holo_mark_accum < HOLO_MARK_INTERVAL:
		return
	_holo_mark_accum = 0.0
	_pulse_hologram_mark()

func _pulse_hologram_mark() -> void:
	if _tier() < 2 or not _hologram_is_valid():
		return
	var center: Vector2 = (_hologram as Node2D).global_position
	_mark_enemies_near(center, HOLO_MARK_RADIUS)

func _mark_enemies_near(center: Vector2, radius: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var radius_sq := radius * radius
	for enemy in tree.get_nodes_in_group("Enemy"):
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		if enemy.is_in_group("SceneProp") or enemy.has_meta("network_remote_enemy"):
			continue
		if not (enemy is Node2D):
			continue
		var stats = enemy.get("stats")
		if stats == null or int(stats.hp) <= 0:
			continue
		if (enemy as Node2D).global_position.distance_squared_to(center) > radius_sq:
			continue
		_apply_kotama_mark(enemy)

func _apply_kotama_mark(enemy: Node) -> void:
	var tier := _tier()
	if tier < 2 or enemy == null or not is_instance_valid(enemy):
		return
	var mgr = enemy.get("enemy_buff_manager")
	if mgr == null or not mgr.has_method("apply_buff"):
		return
	var current = mgr.get("current_buff")
	if current is Dictionary and (current as Dictionary).has("kotama_mark"):
		var entry: Dictionary = (current as Dictionary)["kotama_mark"]
		if float(entry.get("value", 0.0)) < MARK_VULN[tier] - 0.001:
			# 升级到更高档标记时，先移除旧档，避免 max_layer=1 只刷新时长不换数值。
			if mgr.has_method("remove_buff"):
				mgr.remove_buff(KOTAMA_MARK)
	mgr.apply_buff(KOTAMA_MARK, [1, MARK_VULN[tier], MARK_SECONDS], "kotama_ps")

func _has_kotama_mark(enemy: Node) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	var mgr = enemy.get("enemy_buff_manager")
	if mgr == null:
		return false
	var current = mgr.get("current_buff")
	return current is Dictionary and (current as Dictionary).has("kotama_mark")

func _on_bullet_hit_enemy(bullet_body: Node, hit_body: Node) -> void:
	if not _local or _passive_locked:
		return
	if bullet_body == null or not is_instance_valid(bullet_body):
		return
	if not bullet_body.has_meta(BREAK_SHOT_META):
		return
	if hit_body == null or not is_instance_valid(hit_body) or hit_body.is_in_group("SceneProp"):
		return
	var stats = hit_body.get("stats")
	if stats == null or int(stats.hp) > 0:
		return
	_register_break_kill()
	if _tier() >= 3 and _has_kotama_mark(hit_body):
		_try_spawn_execution_echo(hit_body)

func _register_break_kill() -> void:
	if _tier() < 1:
		return
	_break_kills += 1
	var reduction: float = minf(MAX_CD_REDUCTION, float(_break_kills) * KILL_CD_REDUCTION)
	_next_idle_seconds = IDLE_SECONDS * (1.0 - reduction)

func _try_spawn_execution_echo(victim: Node) -> void:
	if _echo_used_in_break or not (victim is Node2D):
		return
	_prune_echoes()
	if not _echo_holograms.is_empty():
		return
	_echo_used_in_break = true
	var pos: Vector2 = (victim as Node2D).global_position
	_mark_enemies_near(pos, ECHO_MARK_RADIUS)
	var layer := _world_layer()
	if layer == null:
		return
	var holo := HOLOGRAM_SCENE.instantiate()
	holo.set("taunt_weight", 1.4)
	layer.add_child(holo)
	holo.global_position = pos
	holo.call("setup", _player_flip())
	holo.call("start_linger", ECHO_LINGER_SECONDS)
	_echo_holograms.append(holo)
	var net_id := _alloc_holo_net_id()
	_connect_holo_net(holo, net_id)
	_broadcast_kotama_event(&"kotama_holo_spawn", {
		"id": net_id,
		"pos": holo.global_position,
		"facing": _player_flip(),
		"weight": 1.4,
	})

func _prune_echoes() -> void:
	for i in range(_echo_holograms.size() - 1, -1, -1):
		var holo = _echo_holograms[i]
		if holo == null or not is_instance_valid(holo) or holo.is_queued_for_deletion():
			_echo_holograms.remove_at(i)

func _clear_echoes() -> void:
	for holo in _echo_holograms:
		if holo == null or not is_instance_valid(holo):
			continue
		if holo.has_method("despawn"):
			holo.call("despawn")
		else:
			holo.queue_free()
	_echo_holograms.clear()

func _reset_break_state() -> void:
	_break_kills = 0
	_next_idle_seconds = IDLE_SECONDS
	_holo_mark_accum = 0.0
	_echo_used_in_break = false

func _world_layer() -> Node:
	var root := get_tree().get_first_node_in_group("PlayerRoot")
	if root != null and root.get_parent() != null:
		return root.get_parent()
	return get_tree().current_scene

func _player_flip() -> bool:
	var sprite = player.get("sprite_2d")
	if sprite != null and sprite is Node2D:
		var flip = sprite.get("flip_h")
		if flip is bool:
			return flip
	var graphics = player.get("graphics")
	if graphics is Node2D:
		return (graphics as Node2D).scale.x < 0.0
	return false

func _hologram_is_valid() -> bool:
	return _hologram != null and is_instance_valid(_hologram)

func _holo_tree_exit_connect(holo: Node) -> void:
	if holo == null:
		return
	if not holo.tree_exited.is_connected(_on_hologram_exited.bind(holo)):
		holo.tree_exited.connect(_on_hologram_exited.bind(holo))

func _on_hologram_exited(holo: Node) -> void:
	if _hologram != holo:
		return
	_hologram = null
	if _phase == Phase.STEALTH:
		_set_stealth_state(false, true)
	_phase = Phase.IDLE
	_shot_idle = 0.0

func _on_player_shot(shot_position: Vector2, bullet_body: Node) -> void:
	_shot_idle = 0.0
	var now := Time.get_ticks_msec()
	if bullet_body != null and is_instance_valid(bullet_body):
		bullet_body.remove_meta(BREAK_SHOT_META)
		bullet_body.remove_meta(BREAK_REFUND_META)
	if _phase == Phase.STEALTH:
		_phase = Phase.BROKEN
		_set_stealth_state(false, true)
		_break_volley_until_msec = now + BREAK_VOLLEY_MS
		_mark_break_bullet(bullet_body)
		_defer_break_crit(bullet_body)
		_spawn_break_muzzle(shot_position, bullet_body)
		if _hologram_is_valid():
			_hologram.call("start_linger", LINGER_SECONDS)
		else:
			_phase = Phase.IDLE
		return
	if now <= _break_volley_until_msec:
		_mark_break_bullet(bullet_body)
		_defer_break_crit(bullet_body)

func _mark_break_bullet(bullet_body: Node) -> void:
	if bullet_body != null and is_instance_valid(bullet_body):
		bullet_body.set_meta(BREAK_SHOT_META, true)
		bullet_body.set_meta(BREAK_REFUND_META, true)

## 在玩家 bullet_hit_damage 完成 base_damage/is_crit 后，再把破隐子弹的暴击预乘进共享 base_damage。
func _defer_break_crit(bullet_body: Node) -> void:
	call_deferred("_apply_break_crit", bullet_body)

func _apply_break_crit(bullet_body: Node) -> void:
	if not _local or bullet_body == null or not is_instance_valid(bullet_body):
		return
	if not bullet_body.has_meta(BREAK_SHOT_META):
		return
	var data = bullet_body.get("damage_data")
	if not (data is DamageData) or data.is_crit:
		return
	var crit_mult := 1.0
	if player != null and is_instance_valid(player) and player.stats != null:
		crit_mult = maxf(1.0, float(player.stats.critical_damage))
	data.is_crit = true
	data.base_damage = maxi(1, int(round(float(data.base_damage) * crit_mult)))

## 破隐首枪的枪口爆发；只在本轮 Phase.STEALTH -> BROKEN 的首发调用。
func _spawn_break_muzzle(shot_position: Vector2, bullet_body: Node) -> void:
	if not PoolManager.fx_allowed(&"muzzle_flash"):
		return
	var layer: Node = get_tree().get_first_node_in_group("SELayer")
	if layer == null:
		layer = _world_layer()
	if layer == null:
		return
	var fx: Node2D = BREAK_MUZZLE_SCENE.instantiate()
	layer.add_child(fx)
	fx.global_position = shot_position
	var angle := 0.0
	if bullet_body != null and is_instance_valid(bullet_body) and bullet_body is Node2D:
		angle = (bullet_body as Node2D).global_rotation
	elif player != null and is_instance_valid(player):
		var target = player.get("crosshair_pos")
		if target is Vector2 and shot_position.distance_squared_to(target) > 0.01:
			angle = shot_position.direction_to(target).angle()
	fx.global_rotation = angle
	_broadcast_kotama_event(&"kotama_break_fx", {
		"pos": shot_position,
		"rot": angle,
	})

func _set_stealth_state(value: bool, silence_on_end: bool = false) -> void:
	if player == null or not is_instance_valid(player):
		return
	var mgr = player.get("player_buff_manager")
	if mgr == null:
		return
	if value:
		mgr.apply_buff(STEALTH_BUFF, [1, 0.0, STEALTH_DURATION], STEALTH_SOURCE)
		if player.has_method("clear_threat_silence"):
			player.call("clear_threat_silence")
	elif silence_on_end and player.has_method("set_threat_silence"):
		mgr.remove_source(STEALTH_BUFF, STEALTH_SOURCE)
		player.call("set_threat_silence", THREAT_SILENCE_SECONDS)
	else:
		mgr.remove_source(STEALTH_BUFF, STEALTH_SOURCE)
		if player.has_method("clear_threat_silence"):
			player.call("clear_threat_silence")
	if _local:
		_broadcast_kotama_event(&"kotama_stealth", {
			"on": value,
			"duration": STEALTH_DURATION,
			"silence": THREAT_SILENCE_SECONDS if (not value and silence_on_end) else 0.0,
		})

func _on_enemy_damage_calculating(_final_damage: int, data: DamageData, _body_path: NodePath) -> void:
	if not _local or data == null or not _is_break_bullet(data):
		return
	var break_mult: float = BREAK_BACKSTAB_MULT_BY_TIER[_tier()]
	var captured := data
	captured.damage_modifier.append(func(victim: Node, amount: int) -> int:
		var out := amount
		if Backstab.is_back(victim):
			out = maxi(1, int(round(float(out) * break_mult)))
		return out
	)

func _is_break_bullet(data: DamageData) -> bool:
	if data == null or data.source_node == NodePath():
		return false
	if data.damage_type.has(GameTags.EXPLOSION_DAMAGE) or data.damage_type.has(GameTags.DOT_DAMAGE) or data.damage_type.has(GameTags.TRUE_DAMAGE):
		return false
	var tree := get_tree()
	if tree == null:
		return false
	var bullet := tree.root.get_node_or_null(data.source_node)
	return bullet != null and bullet.has_meta(BREAK_SHOT_META)

func _on_round_end() -> void:
	_passive_locked = true
	_shot_idle = 0.0
	_clear_all()

func _on_round_upgrade() -> void:
	# 覆盖测试/调试/非标准入口：进入升级页前再次确保没有隐身/全息。
	_passive_locked = true
	_shot_idle = 0.0
	_clear_all()

func _on_round_start() -> void:
	_passive_locked = false
	_shot_idle = 0.0
	_reset_break_state()
	_clear_echoes()
	if player != null and is_instance_valid(player) and player.has_method("clear_threat_silence"):
		player.call("clear_threat_silence")

func _on_test_reset() -> void:
	_passive_locked = false
	_shot_idle = 0.0
	_clear_all()

func _on_game_over(_player_dead: bool) -> void:
	_passive_locked = true
	_clear_all()

func _clear_all(silence_on_end: bool = false) -> void:
	if not _local:
		return
	_set_stealth_state(false, silence_on_end)
	_phase = Phase.IDLE
	_shot_idle = 0.0
	_break_volley_until_msec = 0
	_clear_echoes()
	_reset_break_state()
	if _hologram != null and is_instance_valid(_hologram):
		if _hologram.has_method("despawn"):
			_hologram.call("despawn")
		else:
			_hologram.queue_free()
	_hologram = null

func _connect_remote_cleanup() -> void:
	GameEvents.round_end.connect(_on_remote_cleanup)
	GameEvents.round_upgrade.connect(_on_remote_cleanup)
	GameEvents.round_start.connect(_on_remote_cleanup)
	GameEvents.test_room_reset.connect(_on_remote_cleanup)

func _on_remote_cleanup() -> void:
	_clear_remote_holos()
	if player == null or not is_instance_valid(player):
		return
	var mgr = player.get("player_buff_manager")
	if mgr != null:
		mgr.remove_source(STEALTH_BUFF, KOTAMA_NET_SOURCE)
	if player.has_method("clear_threat_silence"):
		player.call("clear_threat_silence")

func _broadcast_kotama_event(event_name: StringName, data: Dictionary) -> void:
	if not _local or player == null or not is_instance_valid(player):
		return
	if player.has_method("broadcast_character_event"):
		player.call("broadcast_character_event", event_name, data)

func _alloc_holo_net_id() -> int:
	var id := _next_holo_net_id
	_next_holo_net_id += 1
	return id

func _connect_holo_net(holo: Node, net_id: int) -> void:
	if holo != null and is_instance_valid(holo) and holo.has_signal("despawn_started"):
		holo.despawn_started.connect(_on_holo_despawn_started.bind(net_id))

func _on_holo_despawn_started(net_id: int) -> void:
	if not _local:
		return
	_broadcast_kotama_event(&"kotama_holo_despawn", {"id": net_id})

func _clear_remote_holos() -> void:
	var holos: Array = _remote_holos.values()
	_remote_holos.clear()
	for holo in holos:
		if holo == null or not is_instance_valid(holo):
			continue
		if holo.has_method("despawn"):
			holo.call("despawn")
		else:
			holo.queue_free()

func _apply_network_stealth(data: Dictionary) -> void:
	if _local or player == null or not is_instance_valid(player):
		return
	var mgr = player.get("player_buff_manager")
	if mgr == null:
		return
	if bool(data.get("on", false)):
		var duration := clampf(float(data.get("duration", STEALTH_DURATION)), 0.1, STEALTH_DURATION)
		mgr.apply_buff(STEALTH_BUFF, [1, 0.0, duration], KOTAMA_NET_SOURCE)
		if player.has_method("clear_threat_silence"):
			player.call("clear_threat_silence")
	else:
		mgr.remove_source(STEALTH_BUFF, KOTAMA_NET_SOURCE)
		var silence := clampf(float(data.get("silence", 0.0)), 0.0, 2.0)
		if silence > 0.0 and player.has_method("set_threat_silence"):
			player.call("set_threat_silence", silence)
		elif player.has_method("clear_threat_silence"):
			player.call("clear_threat_silence")

func _apply_network_holo_spawn(data: Dictionary) -> void:
	if _local:
		return
	var net_id := int(data.get("id", 0))
	if net_id <= 0:
		return
	var pos = data.get("pos", Vector2.ZERO)
	if not (pos is Vector2):
		return
	var layer := _world_layer()
	if layer == null:
		return
	if _remote_holos.has(net_id):
		_apply_network_holo_despawn({"id": net_id})
	var holo := HOLOGRAM_SCENE.instantiate()
	holo.set("play_smoke_sound", false)
	holo.set("taunt_weight", clampf(float(data.get("weight", 2.0)), 0.1, 4.0))
	layer.add_child(holo)
	holo.global_position = pos
	holo.call("setup", bool(data.get("facing", false)))
	holo.call("start_linger", HOLO_NET_SAFETY_SECONDS)
	_remote_holos[net_id] = holo

func _apply_network_holo_despawn(data: Dictionary) -> void:
	if _local:
		return
	var net_id := int(data.get("id", 0))
	if not _remote_holos.has(net_id):
		return
	var holo = _remote_holos[net_id]
	_remote_holos.erase(net_id)
	if holo == null or not is_instance_valid(holo):
		return
	if holo.has_method("despawn"):
		holo.call("despawn")
	else:
		holo.queue_free()

func _apply_network_break_fx(data: Dictionary) -> void:
	if _local or not PoolManager.fx_allowed(&"muzzle_flash"):
		return
	var pos = data.get("pos", Vector2.ZERO)
	if not (pos is Vector2):
		return
	var layer: Node = get_tree().get_first_node_in_group("SELayer")
	if layer == null:
		layer = _world_layer()
	if layer == null:
		return
	var fx: Node2D = BREAK_MUZZLE_SCENE.instantiate()
	layer.add_child(fx)
	fx.global_position = pos
	fx.global_rotation = float(data.get("rot", 0.0))

func apply_network_character_event(event_name: StringName, event_data: Dictionary) -> void:
	if _local:
		return
	match String(event_name):
		"kotama_stealth":
			_apply_network_stealth(event_data)
		"kotama_holo_spawn":
			_apply_network_holo_spawn(event_data)
		"kotama_holo_despawn":
			_apply_network_holo_despawn(event_data)
		"kotama_break_fx":
			_apply_network_break_fx(event_data)

func _exit_tree() -> void:
	if GameEvents.player_shot_position.is_connected(_on_player_shot):
		GameEvents.player_shot_position.disconnect(_on_player_shot)
	if GameEvents.player_bullet_hit_enemy.is_connected(_on_bullet_hit_enemy):
		GameEvents.player_bullet_hit_enemy.disconnect(_on_bullet_hit_enemy)
	if GameEvents.enemy_damage_calculating.is_connected(_on_enemy_damage_calculating):
		GameEvents.enemy_damage_calculating.disconnect(_on_enemy_damage_calculating)
	if GameEvents.round_end.is_connected(_on_round_end):
		GameEvents.round_end.disconnect(_on_round_end)
	if GameEvents.round_upgrade.is_connected(_on_round_upgrade):
		GameEvents.round_upgrade.disconnect(_on_round_upgrade)
	if GameEvents.round_start.is_connected(_on_round_start):
		GameEvents.round_start.disconnect(_on_round_start)
	if GameEvents.test_room_reset.is_connected(_on_test_reset):
		GameEvents.test_room_reset.disconnect(_on_test_reset)
	if GameEvents.game_over.is_connected(_on_game_over):
		GameEvents.game_over.disconnect(_on_game_over)
	_clear_all()
	_clear_remote_holos()
