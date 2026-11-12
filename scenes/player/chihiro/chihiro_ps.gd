extends PlayerPS
## Chihiro 初始被动：
## 1) 专属无人机装备（环绕、常驻感电、周期放电，作为感电链的传导节点）；
## 2) 射击命中已感电敌人叠「静电」（每层 +1% 异常伤害，上限随 T 提升）；
## 3) 近战（chihiro_melee）由本体释放全部静电，给大范围敌人施加 静电/10 层感电（至少 1 层）。

const SHOCK_ID: String = "shock_dot"
const DRONE_EQUIP := preload("res://scenes/update_item/chihiro_drone.tscn")
const DRONE_BODY := preload("res://scenes/player/chihiro/chihiro_drone_body.tscn")
const DRONE_COUNT: Array[int] = [1, 2, 2, 3]
const ARC_SCENE := preload("res://scenes/debuff/shock_chain_arc.tscn")
const STATIC_BURST_SCENE := preload("res://scenes/effects/chihiro_static_burst.tscn")
const STATIC_BURST_POOL: String = "chihiro_static_burst"

const STATIC_CAP: Array[int] = [99, 199, 499, 999]
const STATIC_PER_LAYER: float = 0.01
const STATIC_SECONDS: float = 9999.0
const RELEASE_RADIUS: float = 320.0

@export var static_buff: Buff
@export var shock_buff: Buff

var _local: bool = false
var _mirror_drones: Array[Node] = []


func _ready() -> void:
	super._ready()
	_local = _is_local_player()
	if not _local:
		call_deferred("_deploy_mirror_drones")
		return
	if not GameEvents.player_bullet_hit_enemy.is_connected(_on_bullet_hit_enemy):
		GameEvents.player_bullet_hit_enemy.connect(_on_bullet_hit_enemy)
	PoolManager.prewarm(STATIC_BURST_POOL, STATIC_BURST_SCENE, 2, "SELayer")
	call_deferred("_deploy_equip")


func _is_local_player() -> bool:
	if player == null or not is_instance_valid(player):
		return false
	if bool(player.get_meta("network_remote_player", false)):
		return false
	return player.is_in_group("Player")


func _tier() -> int:
	return clampi(now_t, 0, 3)


func _static_cap() -> int:
	return STATIC_CAP[_tier()]


func _static_cap_scaled() -> int:
	var mult: float = 1.0
	if player != null and is_instance_valid(player) and player.get("stats") != null:
		mult = maxf(1.0, float(player.stats.buff_layer_mult))
	return maxi(1, int(floor(float(_static_cap()) * mult)))


# ---------------- 装备部署 ----------------

func _deploy_equip() -> void:
	if not _local or player == null or not is_instance_valid(player):
		return
	if player.get_node_or_null("ChihiroDrone") != null:
		return
	var equip = DRONE_EQUIP.instantiate()
	equip.name = "ChihiroDrone"
	player.add_child(equip)


# ---------------- 镜像玩家：纯视觉无人机（不放电/不进链） ----------------

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
	_sync_mirror_drones()


func _sync_mirror_drones() -> void:
	if _local or player == null or not is_instance_valid(player):
		return
	var want: int = DRONE_COUNT[_tier()]
	var host := _host_layer()
	if host == null:
		return
	for i in range(_mirror_drones.size() - 1, -1, -1):
		if not is_instance_valid(_mirror_drones[i]):
			_mirror_drones.remove_at(i)
	while _mirror_drones.size() < want:
		var idx := _mirror_drones.size()
		var d = DRONE_BODY.instantiate()
		d.name = "ChihiroMirrorDrone%d" % idx
		d.set("visual_only", true)
		d.set("player", player)
		d.set("tier", _tier())
		d.set("phase", TAU * float(idx) / float(want))
		host.add_child(d)
		_mirror_drones.append(d)
	while _mirror_drones.size() > want:
		var d = _mirror_drones.pop_back()
		if is_instance_valid(d):
			d.queue_free()
	for i in _mirror_drones.size():
		var d = _mirror_drones[i]
		if not is_instance_valid(d):
			continue
		if d.has_method("set_orbit"):
			d.call("set_orbit", i, _mirror_drones.size())
		if d.has_method("set_tier"):
			d.call("set_tier", _tier())


## 联机：拥有者 PS 升级 → 镜像端按 tier 重建视觉无人机
func network_set_tier(t: int) -> void:
	if _local:
		return
	now_t = clampi(t, 0, 3)
	_sync_mirror_drones()


func _exit_tree() -> void:
	for d in _mirror_drones:
		if is_instance_valid(d):
			d.queue_free()
	_mirror_drones.clear()


# ---------------- 静电：任意玩家子弹命中感电敌人 +1 层 ----------------

func _on_bullet_hit_enemy(bullet: Node, victim: Node) -> void:
	if bullet == null or not is_instance_valid(bullet):
		return
	if victim == null or not is_instance_valid(victim):
		return
	if not victim.is_in_group("Enemy"):
		return
	# 多人：只有该角色自身的玩家子弹才能叠静电（单机下 owner 必为本玩家）
	var shooter = bullet.get("player")
	if shooter == null and bullet.has_method("_ensure_player"):
		shooter = bullet.call("_ensure_player")
	if shooter != null and shooter != player:
		return
	var manager = victim.get("enemy_buff_manager")
	if manager == null:
		return
	var entry = manager.current_buff.get(SHOCK_ID)
	if entry == null or int(entry.get("layer", 0)) <= 0:
		return
	# 每次命中都叠层（同一发子弹反复命中同一敌人也叠）
	player.player_buff_manager.apply_buff(
		static_buff, [_static_cap_scaled(), STATIC_PER_LAYER, STATIC_SECONDS]
	)


func _static_layers() -> int:
	if player == null or not is_instance_valid(player):
		return 0
	var mgr = player.get("player_buff_manager")
	if mgr == null:
		return 0
	var entry = mgr.current_buff.get(static_buff.id)
	if entry == null:
		return 0
	return int(entry.get("layer", 0))


# ---------------- 近战释放 ----------------

func release_static(origin: Vector2) -> void:
	if not _local:
		return
	var layers := _static_layers()
	if layers <= 0:
		return
	# 静电层数/10（向下取整，至少 1 层）= 本次能给敌人补到的感电上限（再受 stats.shock_layer 截断）
	var cap: int = mini(maxi(1, int(floor(float(layers) / 10.0))), int(stats.shock_layer))
	var targets: Array = []
	for e in Targeting.candidates():
		if e == null or not is_instance_valid(e):
			continue
		if e.global_position.distance_to(origin) > RELEASE_RADIUS:
			continue
		var st = e.get("stats")
		if st != null and int(st.get("hp")) <= 0 and not bool(st.get("is_test_target")):
			continue
		if e.get("enemy_buff_manager") == null:
			continue
		targets.append(e)
	var applier := _applier_stats()
	for e in targets:
		var manager = e.get("enemy_buff_manager")
		var entry = manager.current_buff.get(SHOCK_ID)
		var cur: int = int(entry.get("layer", 0)) if entry != null else 0
		var apply_count: int = maxi(0, cap - cur)
		if apply_count > 0:
			for i in apply_count:
				manager.apply_buff(shock_buff, [int(stats.shock_layer), 0.0, 4.0], "chihiro_release", applier)
		elif entry != null:
			# 已 ≥ cap：不加层/不降层，只刷新持续时间（联机由 coop 接管 host 权威）
			if not ExtensionHooks.intercept_named("on_chihiro_refresh_shock", [e]):
				entry["now_time"] = 0
				if manager.has_method("_update_card"):
					manager.call("_update_card", entry)
	# 释放消耗比例：T0 100% / T1 90% / T2 75% / T3 50%（ceil，至少 1 层）
	var ratio: float = [1.0, 0.9, 0.75, 0.5][_tier()]
	var cost: int = maxi(1, int(ceil(float(layers) * ratio)))
	var buff_mgr = player.get("player_buff_manager")
	if buff_mgr != null and buff_mgr.has_method("remove_layers"):
		buff_mgr.call("remove_layers", static_buff, cost)
	elif layers > 0:
		_clear_static()
	_spawn_static_burst(origin)
	_spawn_release_arc(origin, targets, layers)


func _applier_stats() -> Dictionary:
	if stats == null:
		return {}
	return {
		"shock_layer": int(stats.shock_layer),
		"dot_damage": float(stats.dot_damage),
		"dot_time": float(stats.dot_time),
		"global_damage": float(stats.global_damage),
	}


func _clear_static() -> void:
	if player == null or not is_instance_valid(player):
		return
	var mgr = player.get("player_buff_manager")
	if mgr != null and mgr.has_method("remove_buff"):
		mgr.remove_buff(static_buff)


func _spawn_static_burst(origin: Vector2) -> void:
	if not PoolManager.fx_allowed(&"chihiro_static_burst"):
		return
	var layer := get_tree().get_first_node_in_group("SELayer")
	if layer == null:
		return
	var fx = PoolManager.get_pool(STATIC_BURST_POOL)
	if fx == null or fx.is_idle == 0:
		fx = STATIC_BURST_SCENE.instantiate()
		layer.add_child(fx)
	SoundManager.play_sfx("EMP_blast")
	GameEvents.emit_shake_screen(5, 20.0, 0.03)
	fx.play(origin)
	ExtensionHooks.notify_named("on_visual_activated", [fx, {}])


func _spawn_release_arc(origin: Vector2, targets: Array, layers: int) -> void:
	if targets.is_empty():
		return
	if not PoolManager.fx_allowed(&"shock_chain"):
		return
	var layer := get_tree().get_first_node_in_group("SELayer")
	if layer == null:
		return
	var fx = PoolManager.get_pool("shock_chain")
	if fx == null or fx.is_idle == 0:
		fx = ARC_SCENE.instantiate()
		layer.add_child(fx)
		var sfx = fx.get_node_or_null("Sfx")
		if sfx != null:
			sfx.volume_db = -16.0
	var points: Array[Vector2] = [origin]
	for e in targets:
		points.append(e.global_position + Vector2(0, -12))
		if points.size() >= 6:
			break
	fx.play(points, clampi(1 + int(floor(float(layers) / 100.0)), 1, 6))


func ps_upgrade(t_num: int) -> void:
	super.ps_upgrade(t_num)
	if not _local:
		return
	# 最大感电层数：每级 +5（T0 8 / T1 13 / T2 18 / T3 23）
	if PlayerData.base_shock_layer <= 0:
		PlayerData.get_player_base_ability()
	PlayerData.shock_layer_add = maxi(PlayerData.shock_layer_add, 5 * t_num)
	PlayerData.update_player_ability()
	_update_static_cap()
	if player != null and is_instance_valid(player):
		var eq = player.get_node_or_null("ChihiroDrone")
		if eq != null and eq.has_method("set_tier"):
			eq.call("set_tier", _tier())
		# 镜像玩家靠这条事件同步 PS 等级（决定镜像无人机台数）
		ExtensionHooks.notify_named("on_character_event", [player, "chihiro_ps_tier", {"tier": t_num}])


# 升级时只抬高已有静电条目的上限，不清空已攒层数。
func _update_static_cap() -> void:
	if player == null or not is_instance_valid(player):
		return
	var mgr = player.get("player_buff_manager")
	if mgr == null or static_buff == null:
		return
	var entry = mgr.current_buff.get(static_buff.id)
	if entry == null:
		return
	entry["max_layer"] = _static_cap_scaled()
