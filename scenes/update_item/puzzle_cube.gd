extends EquipItem

## 智力魔方：击杀后的溢出伤害在下一拍（global_time_count，10Hz）随机转移给场上敌人。
##
## 转移伤害用 `true_hit`（EQUIP_DAMAGE + TRUE_DAMAGE），因此：
## - 不吃 `global_hurt_damage`（全局易伤类 buff，如 black_ninpero 的 vuln_buff_2）与 damage_modifier；
## - 但**仍吃按类型易伤**（`EnemyStats.equip_hurt_damage_mult`），Hare 的 hare_mark 就在这里放大它。
##
## ⚠️ 转移自身也会走到 HealthComponent 的 `enemy_over_kill_damage`。若把它的溢出再回填，
## 就会形成「溢出 → 转移 → 再溢出」的 10Hz 自反馈；叠上装备易伤后每跳 ×倍率，数值几何增长
## 直至越过 float/int64 边界（刷负数、敌人“回血”）。所以转移统一走 ExtraDamage.request，
## 由它补 GameTags.EXTRA_DAMAGE 标记，本道具再据此拒绝回填（项目既有防递归约定）。

const FOLLOW_ICON := preload("res://scenes/update_item/puzzle_cube_icon.tscn")

## 单次转移上限：兜底防止乘区复利后越过 2^53（float 精度）与 int64 边界。
@export var transfer_cap: int = 999_999

var overflow_count: int = 0
var overflow_cd: int = 0

func _on_equip():
	if not GameEvents.enemy_over_kill_damage.is_connected(dead_overflow_damage):
		GameEvents.enemy_over_kill_damage.connect(dead_overflow_damage)
	if not GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.connect(time_count)
	attach_follow_icon(FOLLOW_ICON)

func _exit_tree():
	if GameEvents.enemy_over_kill_damage.is_connected(dead_overflow_damage):
		GameEvents.enemy_over_kill_damage.disconnect(dead_overflow_damage)
	if GameEvents.global_time_count.is_connected(time_count):
		GameEvents.global_time_count.disconnect(time_count)
	super._exit_tree()

func time_count():
	if overflow_cd > 0:
		overflow_cd -= 1
		if overflow_cd <= 0:
			_transfer_overflow()

func dead_overflow_damage(overkill_damage: int, taken_damage_data: DamageData, _body_path: NodePath):
	# 本道具自己发出的转移伤害（EXTRA_DAMAGE）不再回填，切断自反馈。
	if taken_damage_data != null and taken_damage_data.flags.has(GameTags.EXTRA_DAMAGE):
		return
	if overflow_cd > 0:
		return
	overflow_count = clampi(overkill_damage, 1, transfer_cap)
	overflow_cd = 1

func _transfer_overflow():
	var amount: int = mini(overflow_count, transfer_cap)
	overflow_count = 0 # 消费即清，避免异常路径二次消费残留值
	if amount <= 0:
		return
	var target := _pick_transfer_target()
	if target == null:
		return
	ExtraDamage.request(target, DamageData.true_hit(amount, GameTags.EQUIP, self))

# 只挑「活着、在打、敌方」的目标：死在死亡动画里尚未回池的敌人仍留在活跃表里，
# 对它发起转移会被 HealthComponent 的 hp<=0 门直接吞掉（白丢一次溢出）。
# 不按来源过滤击杀：任何敌方单位的溢出都会转移。
func _pick_transfer_target() -> Node:
	var candidates: Array = []
	for enemy in PoolManager.get_active_enemies():
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.get("is_idle") == 1:
			continue
		var health = enemy.get("health_component")
		if health == null or not health.has_method("request_extra_damage"):
			continue
		if health.get("is_invincible") == true:
			continue
		var stats = enemy.get("stats")
		if stats == null:
			continue
		if stats.hp <= 0 and not stats.is_test_target:
			continue
		if Faction.of_entity(enemy) != Faction.ENEMY_SIDE:
			continue
		candidates.append(enemy)
	if candidates.is_empty():
		return null
	return candidates[randi_range(0, candidates.size() - 1)]
