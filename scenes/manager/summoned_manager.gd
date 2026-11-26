extends Node

signal summoned_changed

# 安全落点工具（静态）。用 preload 引用，避免依赖全局 class 缓存是否已刷新。
const SummonSpawnScript = preload("res://script/summon_spawn.gd")

var summoned_group: Array = []

func _ready():
	PlayerData.player_ability_changed.connect(_refresh_summoned_stats)
	GameEvents.round_start.connect(_on_round_start_rehome)
	GameEvents.terrain_blocks_changed.connect(_on_terrain_blocks_changed)

# 玩家属性变化时统一刷新所有在场召唤物的 stats（O(n) 但只订阅一次）
func _refresh_summoned_stats():
	for i in range(summoned_group.size() - 1, -1, -1):
		var body = summoned_group[i]
		if not is_instance_valid(body):
			summoned_group.remove_at(i)
			continue
		if body.get("stats") != null:
			body.stats.update_body_ability()

# ---------------- 回合开始归位 / 场地墙变化复检 ----------------

# 每回合开始：召唤物离玩家太远或被墙埋住时，回到玩家附近的安全点。
func _on_round_start_rehome() -> void:
	_rehome_summons(true)

# 壁垒建墙/清墙、客机镜像墙落地：只搬被新墙埋住的召唤物（清墙不改变位置）。
func _on_terrain_blocks_changed() -> void:
	_rehome_summons(false)

func _rehome_summons(rehome_far: bool) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var anchor := SummonSpawnScript.player_anchor(self)
	if not anchor.is_finite():
		return
	# 逐个落位并记录已占位，保证同一批召唤物不会叠在同一个点上。
	var placed: Array = []
	for node in tree.get_nodes_in_group("Summoned"):
		if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if not (node is Summoned):
			continue
		var summon := node as Summoned
		if summon.is_idle == 1:
			continue
		# 联机远端镜像由拥有者权威，本机不搬（meta 由 coop 代理写入，单机不存在）。
		if summon.has_meta("is_local_summoned") and not bool(summon.get_meta("is_local_summoned")):
			continue
		var blocked := summon.is_blocked_by_terrain()
		var far := rehome_far and summon.global_position.distance_to(anchor) > summon.home_radius().y
		if blocked or far:
			summon.home_to_player(anchor, placed)
		placed.append(summon.global_position)


func _on_area_2d_body_entered(body):
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Summoned"):
		summoned_group.append(body)
		summoned_changed.emit()


func _on_area_2d_body_exited(body):
	if body == null or not is_instance_valid(body):
		return
	if body.is_in_group("Summoned"):
		summoned_group.remove_at(summoned_group.find(body))
		summoned_changed.emit()
