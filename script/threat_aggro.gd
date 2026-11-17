extends Node

## 通用仇恨权重调度器：
## - 全息注册为候选；Player/RemotePlayer 每 tick 从组中扫描加入同一权重池。
## - 每个敌人独立选一个候选，按权重/距离/确定性 hash 分配，避免全部追第一个。
## - 玩家/远程玩家目标写 threat_target（不关闭 AI/导航场）；全息等非玩家目标写
##   aggro_override（沿用既有直线追击、跳过 EnemyAI 的语义）。
## - 外部 aggro_override（嘲讽/技能/Mod）与 route_target 不覆盖。

const TICK_INTERVAL: float = 0.25
const STICKY_BONUS: float = 1.15

var _candidates: Array[Dictionary] = []
var _tick_accum: float = 0.0

func register(candidate: Node2D, weight: float, radius: float) -> void:
	if candidate == null or not is_instance_valid(candidate):
		return
	for c in _candidates:
		if c.get("node") == candidate:
			c["weight"] = maxf(0.0, weight)
			c["radius"] = maxf(0.0, radius)
			return
	_candidates.append({
		"node": candidate,
		"weight": maxf(0.0, weight),
		"radius": maxf(0.0, radius),
	})

func unregister(candidate: Node2D) -> void:
	for i in range(_candidates.size() - 1, -1, -1):
		if _candidates[i].get("node") == candidate:
			_candidates.remove_at(i)
	# 立即清掉仍指向该候选的受管目标，避免敌人继续追烟雾中的全息。
	var tree := get_tree()
	if tree == null:
		return
	for enemy in tree.get_nodes_in_group("Enemy"):
		if enemy == null or not is_instance_valid(enemy):
			continue
		var changed := false
		if enemy.get("aggro_override") == candidate:
			enemy.set("aggro_override", null)
			changed = true
		if enemy.get("threat_target") == candidate:
			enemy.set("threat_target", null)
			changed = true
		if changed:
			_retarget(enemy)

func _process(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum < TICK_INTERVAL:
		return
	_tick_accum = 0.0
	_tick()

func _tick() -> void:
	var tree := get_tree()
	if tree == null:
		return
	_prune_candidates()
	var candidates := _active_candidates()
	candidates.append_array(_player_candidates(candidates))
	var enemies := tree.get_nodes_in_group("Enemy")
	if candidates.is_empty():
		for enemy in enemies:
			_clear_managed_target(enemy)
		return
	for enemy in enemies:
		if not _enemy_eligible(enemy):
			_clear_managed_target(enemy)
			continue
		if _has_valid_route(enemy):
			# 路线型敌人由 enemy_path 接管；清掉我们自己的目标，避免残留覆盖路线。
			_clear_managed_target(enemy)
			continue
		var external = enemy.get("aggro_override")
		if external != null and not is_instance_valid(external):
			enemy.set("aggro_override", null)
			external = null
		if external != null and not _is_registered(external):
			# 外部嘲讽/技能：完全不动；清掉我们自己的 threat_target，避免外部结束后串味。
			if enemy.get("threat_target") != null:
				enemy.set("threat_target", null)
			continue
		var current = _current_managed_target(enemy)
		var best := _pick_target(enemy, candidates, current)
		if best == null:
			_clear_managed_target(enemy)
			continue
		if best == current:
			continue
		if _is_player_target(best):
			# 玩家目标：写 threat_target，保留 EnemyAI；若当前是自己的全息 override，先清掉。
			if external != null and _is_registered(external):
				enemy.set("aggro_override", null)
			enemy.set("threat_target", best)
		else:
			# 全息目标：沿用 aggro_override 的直线追击/跳过 AI 语义。
			enemy.set("aggro_override", best)
			enemy.set("threat_target", null)
		_retarget(enemy)

func _enemy_eligible(enemy) -> bool:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
		return false
	if not (enemy is Node2D):
		return false
	# EnemyPart（护盾/手臂等）也挂在 "Enemy" 组，但没有目标/override 字段；统一跳过。
	if enemy.is_in_group("EnemyPart"):
		return false
	if enemy.is_in_group("SceneProp") or enemy.has_meta("network_remote_enemy"):
		return false
	if enemy.get("faction") == null or int(enemy.get("faction")) == Faction.PLAYER_SIDE:
		return false
	if enemy.get("is_idle") == 1:
		return false
	var stats = enemy.get("stats")
	return stats != null and int(stats.hp) > 0

func _prune_candidates() -> void:
	for i in range(_candidates.size() - 1, -1, -1):
		var c: Dictionary = _candidates[i]
		var node = c.get("node")
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			_candidates.remove_at(i)
		elif node.get("_despawning") == true:
			_candidates.remove_at(i)

func _active_candidates() -> Array:
	var out: Array = []
	for c in _candidates:
		var node = c.get("node")
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.get("is_downed") == true:
			continue
		if node.has_method("is_stealthed") and node.is_stealthed():
			continue
		if node.has_method("is_threat_silenced") and node.is_threat_silenced():
			continue
		out.append(c)
	return out

func _is_registered(node) -> bool:
	for c in _candidates:
		if c.get("node") == node:
			return true
	return false

func _player_candidates(existing: Array) -> Array:
	var out: Array = []
	var seen := {}
	for c in existing:
		var n = c.get("node")
		if n != null:
			seen[n.get_instance_id()] = true
	var tree := get_tree()
	if tree == null:
		return out
	for group_name in ["Player", "RemotePlayer"]:
		for node in tree.get_nodes_in_group(group_name):
			if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			if not (node is Node2D):
				continue
			if seen.has(node.get_instance_id()):
				continue
			if node.get("is_downed") == true:
				continue
			if node.has_method("is_stealthed") and node.is_stealthed():
				continue
			if node.has_method("is_threat_silenced") and node.is_threat_silenced():
				continue
			var weight := 1.0
			var raw = node.get("threat_weight")
			if raw is float or raw is int:
				weight = maxf(0.0, float(raw))
			seen[node.get_instance_id()] = true
			out.append({"node": node, "weight": weight, "radius": 0.0})
	return out

func _is_player_target(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return node.is_in_group("Player") or node.is_in_group("RemotePlayer")

func _has_valid_route(enemy) -> bool:
	var route = enemy.get("route_target")
	return route != null and is_instance_valid(route)

## 当前实际受管目标：已注册的全息 override 优先，否则 threat_target。
## 失效引用顺手清掉，避免继续参与 sticky 比较。
func _current_managed_target(enemy):
	var managed = enemy.get("aggro_override")
	if managed != null:
		if not is_instance_valid(managed):
			enemy.set("aggro_override", null)
			managed = null
		elif _is_registered(managed):
			return managed
	var threat = enemy.get("threat_target")
	if threat != null and not is_instance_valid(threat):
		enemy.set("threat_target", null)
		threat = null
	return threat

## 只清 ThreatAggro 自己写下的目标；绝不碰外部 aggro_override。
func _clear_managed_target(enemy) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var changed := false
	var managed = enemy.get("aggro_override")
	if managed != null:
		if not is_instance_valid(managed) or _is_registered(managed):
			enemy.set("aggro_override", null)
			changed = true
	if enemy.get("threat_target") != null:
		enemy.set("threat_target", null)
		changed = true
	if changed:
		_retarget(enemy)

func _pick_target(enemy: Node2D, candidates: Array, current) -> Node2D:
	var best: Node2D = null
	var best_score := -1.0
	for c in candidates:
		var node: Node2D = c.get("node")
		var weight: float = float(c.get("weight", 0.0))
		var radius: float = float(c.get("radius", 0.0))
		if weight <= 0.0:
			continue
		var dist := enemy.global_position.distance_to(node.global_position)
		if radius > 0.0 and dist > radius:
			continue
		var proximity := 1.0 if radius <= 0.0 else clampf(1.0 - dist / radius, 0.05, 1.0)
		var effective := weight * (0.6 + 0.4 * proximity)
		if current == node:
			effective *= STICKY_BONUS
		var score := pow(_hash01(enemy.get_instance_id(), node.get_instance_id()), 1.0 / maxf(effective, 0.01))
		if score > best_score:
			best_score = score
			best = node
	return best

func _retarget(enemy) -> void:
	if enemy != null and is_instance_valid(enemy) and enemy.has_method("force_retarget"):
		enemy.force_retarget()

func _hash01(a: int, b: int) -> float:
	var h := int(hash([a, b]))
	return float((h & 0x7FFFFFFF) % 10000) / 10000.0
