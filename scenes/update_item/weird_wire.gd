extends ShockEquipItem

# 贵重电缆：感电目标死亡时，把它残留的感电层数传导给周围的敌人。
# 只负责「铺场」，伤害仍由 ShockChain 在下一跳结算；传导本身不造成伤害，所以不会自递归。

const RADIUS := 200.0
## 同一物理帧内的传导次数上限：防止一条长链连续死亡时同帧雪崩。
const FRAME_SPREAD_LIMIT := 3

var _target_count: int = 2
var _last_frame: int = -1
var _frame_spreads: int = 0

func _setup() -> void:
	GameEvents.enemy_damage_taken_dead.connect(_on_enemy_dead)

func _apply_effect(quantity: int) -> void:
	_target_count = 1 + quantity

func _on_enemy_dead(_final_damage: int, _damage_data: DamageData, body_path: NodePath) -> void:
	var dead := get_node_or_null(body_path)
	if dead == null or not is_instance_valid(dead):
		return
	# 死亡信号是同步发出的（health_component 先 emit 再清 buff），此处仍能读到层数。
	var layers := shock_layer_of(dead)
	if layers <= 0:
		return
	var frame := Engine.get_physics_frames()
	if frame != _last_frame:
		_last_frame = frame
		_frame_spreads = 0
	if _frame_spreads >= FRAME_SPREAD_LIMIT:
		return
	var origin: Vector2 = dead.global_position
	# 只收集半径内的候选（不再对全表排序：105 敌整表排序 ≈183µs/次），
	# 再「每轮取最近的一个」尝试施加 —— 保留原语义：最近者打满层就顺延到下一个，直到成功 N 个。
	var in_range: Array = []
	for enemy in Targeting.candidates():
		if enemy == dead or enemy == null or not is_instance_valid(enemy):
			continue
		var d: float = origin.distance_to(enemy.global_position)
		if d > RADIUS:
			continue
		in_range.append({"e": enemy, "d": d})
	var spread := 0
	while spread < _target_count and not in_range.is_empty():
		var best_i := -1
		var best_d := INF
		for i in in_range.size():
			var dd: float = float(in_range[i]["d"])
			if dd < best_d:
				best_d = dd
				best_i = i
		if best_i < 0:
			break
		var enemy = in_range[best_i]["e"]
		in_range.remove_at(best_i)
		if enemy == null or not is_instance_valid(enemy):
			continue
		if apply_shock(enemy, layers) <= 0:
			continue
		spawn_shock_arc(origin, enemy.global_position, 3)
		spread += 1
	if spread > 0:
		_frame_spreads += 1
