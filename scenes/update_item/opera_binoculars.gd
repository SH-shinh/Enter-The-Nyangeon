extends EquipItem

# 歌剧望远镜：召唤物暴击伤害 ×2，非暴击伤害 ×0.5（最小 1）。
#
# 只监听召唤物开火的暴击 / 非暴击信号（拥有者端才会发出），在子弹生成时改写
# 该发 damage_data.base_damage；DamageData 每发由 DamageData.fill 重置，
# 弹池复用不会残留倍率。
#
# 期望倍率 = 0.5 + 1.5×暴击率：暴击率约 33% 时与装备前持平，越高越赚。

const CRIT_MULT: float = 2.0
const NON_CRIT_MULT: float = 0.5

func _setup() -> void:
	GameEvents.summoned_shot_critical.connect(_on_summoned_shot_critical)
	GameEvents.summoned_shot_not_critical.connect(_on_summoned_shot_not_critical)
	if not PlayerData.reset_done.is_connected(_on_player_reset):
		PlayerData.reset_done.connect(_on_player_reset)

## 测试房重置只清部分节点、本道具仍挂在玩家下；本局已不再记录它时自清理，
## 否则旧节点会与重新抽到的新节点叠加（暴击 ×4）。
func _on_player_reset() -> void:
	if item_id != "" and not PlayerData.current_upgrades.has(item_id):
		queue_free()

func _on_summoned_shot_critical(bullet_body: Node) -> void:
	_scale_damage(bullet_body, CRIT_MULT)

func _on_summoned_shot_not_critical(bullet_body: Node) -> void:
	_scale_damage(bullet_body, NON_CRIT_MULT)

func _scale_damage(bullet_body: Node, mult: float) -> void:
	if bullet_body == null or not is_instance_valid(bullet_body):
		return
	var damage_data = bullet_body.get("damage_data")
	if not (damage_data is DamageData):
		return
	damage_data.base_damage = maxi(1, int(round(float(damage_data.base_damage) * mult)))
