extends ShockEquipItem

# 改造零件：召唤物伤害命中时给目标叠 1 层感电。
#
# 判定：只认 damage_data.source_type 里的 SUMMONED 标签。
#   - mobu / Kei 的枪走 scenes/player_support/kei/luminous_nova.gd，source = SUMMONED；
#   - Utaha 炮塔走 script/turret_summoned.gd，同样是 SUMMONED；
#   - 玩家子弹（PLAYER）、策反单位（CONVERTED）、装备伤害（EQUIP）都不会命中本过滤。
# 施加统一走 ShockEquipItem.apply_shock → enemy_buff_manager.apply_buff，这是联机唯一安全通道。
#
# 频率：mobu 射速约 0.25s/发，每发都施加会很快顶满 stats.shock_layer，且 apply_buff 的开销
# 与网络转发会跟着刷屏，所以按「每目标冷却」节流，而不是按命中次数计数。

## 同一目标两次感电的最小间隔（秒）：按持有件数取，最多 3 件。
const CD_BY_QUANTITY: Array[float] = [1.0, 0.6, 0.3]
## 冷却字典上限：超过就清理已释放的实例 id。
const MAX_TRACKED: int = 64

var _next_ready: Dictionary = {}
var _cooldown: float = CD_BY_QUANTITY[0]

func _apply_effect(quantity: int) -> void:
	_cooldown = CD_BY_QUANTITY[clampi(quantity - 1, 0, CD_BY_QUANTITY.size() - 1)]

func _setup() -> void:
	GameEvents.enemy_damage_taken.connect(_on_enemy_damage_taken)

func _on_enemy_damage_taken(_final_damage: int, damage_data: DamageData, body_path: NodePath) -> void:
	if damage_data == null or not damage_data.source_type.has(GameTags.SUMMONED):
		return
	var enemy: Node = get_node_or_null(body_path)
	if enemy == null or not is_instance_valid(enemy):
		return
	enemy = resolve_enemy_body(enemy)
	if enemy == null:
		return
	if not _combo_ready(enemy):
		return
	apply_shock(enemy, 1)
	_prune_tracking()

# 先占冷却再出效果：避免同一帧多弹丸/多召唤物命中把同一目标反复施加。
func _combo_ready(enemy: Node) -> bool:
	var key: int = enemy.get_instance_id()
	var now: int = Time.get_ticks_msec()
	if int(_next_ready.get(key, -1)) > now:
		return false
	_next_ready[key] = now + int(round(_cooldown * 1000.0))
	return true

func _prune_tracking() -> void:
	for key in _next_ready.keys():
		if not is_instance_id_valid(int(key)):
			_next_ready.erase(key)
	if _next_ready.size() <= MAX_TRACKED:
		return
	# Dictionary 保序：仍超限就丢最旧的键，保证真正封顶。
	for key in _next_ready.keys():
		if _next_ready.size() <= MAX_TRACKED:
			return
		_next_ready.erase(key)
