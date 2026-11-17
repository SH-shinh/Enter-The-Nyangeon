extends Node

## 通用仇恨权重调度器：
## - 全息注册为候选；Player/RemotePlayer 每 tick 从组中扫描加入同一权重池。
## - 每个敌人独立选一个候选，按权重/距离/确定性 hash 分配，避免全部追第一个。
## - 只写 Enemy.aggro_override；尊重外部 override 与 route_target。

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
	# 立即清掉仍指向该候选的 override，避免敌人继续追烟雾中的全息。
	var tree := get_tree()
	if tree == null:
		return
	for enemy in tree.get_nodes_in_group("Enemy"):
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.get("aggro_override") == candidate:
			enemy.set("aggro_override", null)
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
	if candidates.is_empty():
		return
	for enemy in tree.get_nodes_in_group("Enemy"):
		if not _enemy_eligible(enemy):
			continue
		if enemy.get("route_target") != null and is_instance_valid(enemy.get("route_target")):
			continue
		var current = enemy.get("aggro_override")
		if current != null and is_instance_valid(current) and not _is_managed(current):
			# 外部嘲讽/技能：不覆盖，等它自己结束。
			continue
		var best := _pick_target(enemy, candidates, current)
		if best == null:
			if current != null and _is_managed(current):
				enemy.set("aggro_override", null)
				_retarget(enemy)
			continue
		if current != best:
			enemy.set("aggro_override", best)
			_retarget(enemy)

func _enemy_eligible(enemy) -> bool:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
		return false
	if not (enemy is Node2D):
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
		out.append(c)
	return out

func _is_registered(node) -> bool:
	for c in _candidates:
		if c.get("node") == node:
			return true
	return false

func _is_managed(node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if _is_registered(node):
		return true
	return node.is_in_group("Player") or node.is_in_group("RemotePlayer")

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
			var weight := 1.0
			var raw = node.get("threat_weight")
			if raw is float or raw is int:
				weight = maxf(0.0, float(raw))
			seen[node.get_instance_id()] = true
			out.append({"node": node, "weight": weight, "radius": 0.0})
	return out

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
