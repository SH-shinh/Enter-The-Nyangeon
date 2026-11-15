extends ShockEquipItem

# 神秘线缆：对同一敌人累计命中到阈值后，给它叠 1 层感电。
# 计数按敌人 instance_id 分开记；穿透/多弹丸各自算一次命中（都走 bullet 的 on_damage_dealt）。

## 同时追踪的敌人上限：超过就清掉已释放的 id，避免长时间局字典膨胀。
const MAX_TRACKED := 64

var _hits: Dictionary = {}
var _threshold: int = 8

func _setup() -> void:
	GameEvents.player_bullet_hit_enemy.connect(_on_bullet_hit_enemy)

func _apply_effect(quantity: int) -> void:
	# 第 1/2/3 件：8/7/6 次命中一层；下限 4，避免叠太多后一次命中一层。
	_threshold = maxi(4, 9 - quantity)

func _on_bullet_hit_enemy(_bullet_body: Node, hit_body: Node) -> void:
	var enemy := resolve_enemy_body(hit_body)
	if enemy == null:
		return
	var key: int = enemy.get_instance_id()
	var count: int = int(_hits.get(key, 0)) + 1
	if count < _threshold:
		_hits[key] = count
		return
	_hits.erase(key)
	if apply_shock(enemy, 1) > 0:
		spawn_shock_arc(player_center(), enemy.global_position)
	_prune_tracking()

func _prune_tracking() -> void:
	for key in _hits.keys():
		if not is_instance_id_valid(int(key)):
			_hits.erase(key)
	if _hits.size() <= MAX_TRACKED:
		return
	# Dictionary 保序：仍超限就丢最旧的键，保证真正封顶。
	for key in _hits.keys():
		if _hits.size() <= MAX_TRACKED:
			return
		_hits.erase(key)
